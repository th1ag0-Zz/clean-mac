import Darwin
import Foundation

actor CleanupEngine {
    private let exclusions: AnalysisExclusions

    init(exclusions: AnalysisExclusions = AnalysisExclusions()) {
        self.exclusions = exclusions
    }

    func makePlan(from result: AnalysisResult, selectedPaths: Set<String>) throws -> CleanupPlan {
        let home = try ScanScope.homeDirectory()
        guard !selectedPaths.isEmpty else { throw CleanupError.emptySelection }
        let selected = result.candidates.filter { selectedPaths.contains($0.relativePath) }
        guard selected.count == selectedPaths.count else { throw CleanupError.unknownSelection }
        guard selected.allSatisfy({ isCatalogued($0, home: home) && !isExcluded($0.relativePath) }) else {
            throw CleanupError.invalidPlan
        }
        return CleanupPlan(home: home, items: selected, createdAt: Date())
    }

    func execute(
        _ plan: CleanupPlan,
        progress: (@Sendable (CleanupProgress) -> Void)? = nil
    ) throws -> CleanupReport {
        let home = try ScanScope.homeDirectory()
        guard plan.home == home, !plan.items.isEmpty,
              plan.items.allSatisfy({ isCatalogued($0, home: home) }) else {
            throw CleanupError.invalidPlan
        }

        var outcomes: [CleanupOutcome] = []
        for candidate in plan.items {
            let outcome: CleanupOutcome
            if isExcluded(candidate.relativePath) {
                outcome = CleanupOutcome(candidate: candidate, destination: nil,
                                         error: "O item foi excluído da análise antes da limpeza.")
            } else {
                outcome = moveValidated(candidate, home: home)
            }
            outcomes.append(outcome)
            progress?(CleanupProgress(processed: outcomes.count, total: plan.items.count,
                                      currentPath: candidate.relativePath))
        }
        return CleanupReport(outcomes: outcomes)
    }

    private func isExcluded(_ relativePath: String) -> Bool {
        exclusions.all().contains { excluded in
            relativePath == excluded || relativePath.hasPrefix(excluded + "/")
        }
    }

    private func isCatalogued(_ candidate: AnalysisCandidate, home: URL) -> Bool {
        let parts = candidate.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              candidate.url.standardizedFileURL == home.appendingPathComponent(candidate.relativePath).standardizedFileURL,
              let rule = AnalysisCatalog.rules.first(where: { $0.category == candidate.category }),
              parts.count > rule.directoryComponents.count,
              (rule.recursive || parts.count == rule.directoryComponents.count + 1),
              Array(parts.prefix(rule.directoryComponents.count)).map(String.init) == rule.directoryComponents,
              rule.accepts(fileName: String(parts.last!), modifiedAt: candidate.modifiedAt, now: Date()),
              candidate.logicalBytes == candidate.identity.logicalBytes else { return false }
        return true
    }

    private func moveValidated(_ candidate: AnalysisCandidate, home: URL) -> CleanupOutcome {
        do {
            let opened = try openValidated(candidate, home: home)
            defer { close(opened.fileFD); close(opened.parentFD) }
            let destination: URL
            if ScanScope.isFixture {
            destination = try moveToFixtureTrash(candidate, home: home, parentFD: opened.parentFD)
            } else {
            var movedURL: NSURL?
            try FileManager.default.trashItem(at: candidate.url, resultingItemURL: &movedURL)
            guard let movedURL else { throw CleanupValidationError.destinationNotConfirmed }
            destination = movedURL as URL
            }

            var movedStat = stat()
            guard lstat(destination.path, &movedStat) == 0,
                  matchesMovedFile(movedStat, identity: candidate.identity) else {
                // Se houve troca de caminho durante a operação, tenta restaurar o item.
                try? FileManager.default.moveItem(at: destination, to: candidate.url)
                throw CleanupValidationError.destinationNotConfirmed
            }
            return CleanupOutcome(candidate: candidate, destination: destination, error: nil)
        } catch {
            return CleanupOutcome(candidate: candidate, destination: nil,
                                  error: error.localizedDescription)
        }
    }

    private func openValidated(
        _ candidate: AnalysisCandidate, home: URL
    ) throws -> (parentFD: Int32, fileFD: Int32) {
        guard isCatalogued(candidate, home: home) else { throw CleanupValidationError.notEligible }
        let homeFD = open(home.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard homeFD >= 0 else { throw CleanupValidationError.inaccessible }
        var currentFD = homeFD
        var homeStat = stat()
        guard fstat(homeFD, &homeStat) == 0 else {
            close(homeFD)
            throw CleanupValidationError.inaccessible
        }

        let parts = candidate.relativePath.split(separator: "/").map(String.init)
        var path = home
        for component in parts.dropLast() {
            let nextFD = component.withCString {
                openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            close(currentFD)
            guard nextFD >= 0 else { throw CleanupValidationError.changed }
            currentFD = nextFD
            path.appendPathComponent(component, isDirectory: true)
            var openedStat = stat()
            var pathStat = stat()
            guard fstat(currentFD, &openedStat) == 0,
                  lstat(path.path, &pathStat) == 0,
                  openedStat.st_dev == homeStat.st_dev,
                  openedStat.st_dev == pathStat.st_dev,
                  openedStat.st_ino == pathStat.st_ino,
                  openedStat.st_mode & S_IFMT == S_IFDIR else {
                close(currentFD)
                throw CleanupValidationError.changed
            }
        }

        let fileFD = parts.last!.withCString {
            openat(currentFD, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard fileFD >= 0 else {
            close(currentFD)
            throw CleanupValidationError.changed
        }
        guard flock(fileFD, LOCK_SH | LOCK_NB) == 0 else {
            close(fileFD); close(currentFD)
            throw CleanupValidationError.busy
        }
        var openedStat = stat()
        var pathStat = stat()
        guard fstat(fileFD, &openedStat) == 0,
              lstat(candidate.url.path, &pathStat) == 0,
              openedStat.st_dev == homeStat.st_dev,
              openedStat.st_mode & S_IFMT == S_IFREG,
              openedStat.st_nlink == 1,
              matches(openedStat, identity: candidate.identity),
              matches(pathStat, identity: candidate.identity) else {
            close(fileFD); close(currentFD)
            throw CleanupValidationError.changed
        }
        return (currentFD, fileFD)
    }

    private func matches(_ info: stat, identity: FileIdentity) -> Bool {
        info.st_dev == identity.device &&
        info.st_ino == identity.inode &&
        info.st_size == identity.logicalBytes &&
        info.st_mtimespec.tv_sec == identity.modifiedSeconds &&
        info.st_mtimespec.tv_nsec == identity.modifiedNanoseconds &&
        info.st_ctimespec.tv_sec == identity.changedSeconds &&
        info.st_ctimespec.tv_nsec == identity.changedNanoseconds &&
        info.st_mode == identity.mode
    }

    private func matchesMovedFile(_ info: stat, identity: FileIdentity) -> Bool {
        info.st_dev == identity.device &&
        info.st_ino == identity.inode &&
        info.st_size == identity.logicalBytes &&
        info.st_mtimespec.tv_sec == identity.modifiedSeconds &&
        info.st_mtimespec.tv_nsec == identity.modifiedNanoseconds &&
        info.st_mode == identity.mode
    }

    private func moveToFixtureTrash(
        _ candidate: AnalysisCandidate, home: URL, parentFD: Int32
    ) throws -> URL {
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let trashFD = open(trash.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard trashFD >= 0 else { throw CleanupValidationError.inaccessible }
        defer { close(trashFD) }
        var trashStat = stat()
        var homeStat = stat()
        guard fstat(trashFD, &trashStat) == 0,
              stat(home.path, &homeStat) == 0,
              trashStat.st_dev == homeStat.st_dev else {
            throw CleanupValidationError.inaccessible
        }
        let name = UUID().uuidString + "-" + candidate.url.lastPathComponent
        let moved = candidate.url.lastPathComponent.withCString { source in
            name.withCString { target in renameat(parentFD, source, trashFD, target) }
        }
        guard moved == 0 else { throw CleanupValidationError.inaccessible }
        return trash.appendingPathComponent(name)
    }
}

private enum CleanupValidationError: LocalizedError {
    case notEligible
    case inaccessible
    case changed
    case busy
    case destinationNotConfirmed

    var errorDescription: String? {
        switch self {
        case .notEligible: "Item fora do catálogo permitido."
        case .inaccessible: "Não foi possível acessar ou mover o item."
        case .changed: "O item mudou desde a análise; faça uma nova análise."
        case .busy: "O item está em uso."
        case .destinationNotConfirmed: "Não foi possível confirmar o item na Lixeira."
        }
    }
}
