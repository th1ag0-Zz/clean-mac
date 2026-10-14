import Darwin
import Foundation

actor AnalysisEngine {
    private let exclusions: AnalysisExclusions

    init(exclusions: AnalysisExclusions = AnalysisExclusions()) {
        self.exclusions = exclusions
    }

    /// Pode ser chamado novamente após uma alteração ou edição das exclusões.
    func analyze(progress: (@Sendable (AnalysisProgress) -> Void)? = nil) throws -> AnalysisResult {
        let home = try ScanScope.homeDirectory()
        let excludedPaths = exclusions.all()
        var walker = ScanWalker(home: home, excludedPaths: excludedPaths, progress: progress)
        return try walker.scan()
    }

    func exclude(_ candidate: AnalysisCandidate) {
        exclusions.exclude(candidate.relativePath)
    }

    func exclude(relativePath: String) {
        exclusions.exclude(relativePath)
    }

    func include(relativePath: String) {
        exclusions.include(relativePath)
    }

    func excludedPaths() -> Set<String> {
        exclusions.all()
    }
}

private struct ScanWalker {
    let home: URL
    let excludedPaths: Set<String>
    let progress: (@Sendable (AnalysisProgress) -> Void)?
    private(set) var candidates: [AnalysisCandidate] = []
    private(set) var issues: [AnalysisIssue] = []
    private var seenFiles: Set<FileKey> = []
    private var scannedEntries = 0
    private var foundLogicalBytes: UInt64 = 0
    private let now = Date()
    private let maximumDepth = 16

    mutating func scan() throws -> AnalysisResult {
        try Task.checkCancellation()
        let homeFD = open(home.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard homeFD >= 0 else {
            throw ScanError.cannotOpenHome
        }
        defer { close(homeFD) }

        var homeStat = stat()
        guard fstat(homeFD, &homeStat) == 0 else {
            throw ScanError.cannotOpenHome
        }

        for rule in AnalysisCatalog.rules {
            try Task.checkCancellation()
            reportProgress(for: rule.category)
            let relativePath = rule.directoryComponents.joined(separator: "/")
            if isExcluded(relativePath) { continue }
            guard let directoryFD = openDirectory(
                components: rule.directoryComponents,
                under: homeFD,
                device: homeStat.st_dev
            ) else { continue }
            defer { close(directoryFD) }
            try walk(directoryFD: directoryFD, relativeDirectory: relativePath,
                     rule: rule, device: homeStat.st_dev, depth: 0)
            reportProgress(for: rule.category)
        }

        candidates.sort {
            if $0.category != $1.category {
                return AnalysisCategory.allCases.firstIndex(of: $0.category)! <
                    AnalysisCategory.allCases.firstIndex(of: $1.category)!
            }
            if $0.logicalBytes != $1.logicalBytes { return $0.logicalBytes > $1.logicalBytes }
            return $0.relativePath < $1.relativePath
        }
        return AnalysisResult(scannedAt: now, candidates: candidates, issues: issues)
    }

    private mutating func openDirectory(
        components: [String], under homeFD: Int32, device: dev_t
    ) -> Int32? {
        var currentFD = dup(homeFD)
        guard currentFD >= 0 else { return nil }
        var path = ""
        for component in components {
            path = path.isEmpty ? component : path + "/" + component
            let nextFD = component.withCString {
                openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            let openError = errno
            close(currentFD)
            guard nextFD >= 0 else {
                if openError != ENOENT {
                    issues.append(AnalysisIssue(relativePath: path, kind: .inaccessible))
                }
                return nil
            }
            var info = stat()
            guard fstat(nextFD, &info) == 0, info.st_dev == device else {
                issues.append(AnalysisIssue(relativePath: path, kind: .inaccessible))
                close(nextFD)
                return nil
            }
            currentFD = nextFD
        }
        return currentFD
    }

    private mutating func walk(
        directoryFD: Int32, relativeDirectory: String,
        rule: AnalysisRule, device: dev_t, depth: Int
    ) throws {
        try Task.checkCancellation()
        let streamFD = dup(directoryFD)
        guard streamFD >= 0, let stream = fdopendir(streamFD) else {
            if streamFD >= 0 { close(streamFD) }
            issues.append(AnalysisIssue(relativePath: relativeDirectory, kind: .readFailed))
            return
        }
        defer { closedir(stream) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            try Task.checkCancellation()
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        if errno != 0 {
            issues.append(AnalysisIssue(relativePath: relativeDirectory, kind: .readFailed))
        }

        for name in names.sorted() {
            try Task.checkCancellation()
            scannedEntries += 1
            if scannedEntries.isMultiple(of: 50) { reportProgress(for: rule.category) }
            let relativePath = relativeDirectory + "/" + name
            if isExcluded(relativePath) { continue }
            var before = stat()
            let metadataResult = name.withCString {
                fstatat(directoryFD, $0, &before, AT_SYMLINK_NOFOLLOW)
            }
            guard metadataResult == 0 else {
                issues.append(AnalysisIssue(relativePath: relativePath, kind: .changedDuringScan))
                continue
            }
            guard before.st_dev == device else { continue }
            let fileType = before.st_mode & S_IFMT
            if fileType == S_IFDIR {
                if !rule.recursive { continue }
                guard depth < maximumDepth else {
                    issues.append(AnalysisIssue(relativePath: relativePath, kind: .depthLimit))
                    continue
                }
                let childFD = name.withCString {
                    openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard childFD >= 0 else {
                    issues.append(AnalysisIssue(relativePath: relativePath, kind: .changedDuringScan))
                    continue
                }
                defer { close(childFD) }
                var opened = stat()
                if fstat(childFD, &opened) == 0 &&
                    opened.st_dev == device && opened.st_ino == before.st_ino {
                    try walk(directoryFD: childFD, relativeDirectory: relativePath,
                             rule: rule, device: device, depth: depth + 1)
                } else {
                    issues.append(AnalysisIssue(relativePath: relativePath, kind: .changedDuringScan))
                }
            } else if fileType == S_IFREG {
                inspectFile(name: name, relativePath: relativePath,
                            directoryFD: directoryFD, before: before, rule: rule)
            }
            // Links simbólicos, sockets, dispositivos e arquivos de outro volume ficam fora.
        }
    }

    private func isExcluded(_ relativePath: String) -> Bool {
        excludedPaths.contains(relativePath) || excludedPaths.contains {
            relativePath.hasPrefix($0 + "/")
        }
    }

    private mutating func inspectFile(
        name: String, relativePath: String, directoryFD: Int32,
        before: stat, rule: AnalysisRule
    ) {
        guard before.st_nlink == 1, before.st_size >= 0 else { return }
        let modifiedAt = Date(
            timeIntervalSince1970: TimeInterval(before.st_mtimespec.tv_sec) +
                TimeInterval(before.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        guard rule.accepts(fileName: name, modifiedAt: modifiedAt, now: now) else { return }

        let fileFD = name.withCString {
            openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard fileFD >= 0 else {
            issues.append(AnalysisIssue(relativePath: relativePath, kind: .inaccessible))
            return
        }
        defer { close(fileFD) }
        guard flock(fileFD, LOCK_SH | LOCK_NB) == 0 else {
            issues.append(AnalysisIssue(relativePath: relativePath, kind: .busy))
            return
        }
        defer { flock(fileFD, LOCK_UN) }

        var opened = stat()
        let url = home.appendingPathComponent(relativePath, isDirectory: false)
        var atPath = stat()
        guard fstat(fileFD, &opened) == 0,
              lstat(url.path, &atPath) == 0,
              FileKey(opened) == FileKey(before),
              FileKey(atPath) == FileKey(before),
              opened.st_size == before.st_size,
              opened.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              opened.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
              opened.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec,
              opened.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec,
              atPath.st_size == before.st_size,
              atPath.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              atPath.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
              atPath.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec,
              atPath.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else {
            issues.append(AnalysisIssue(relativePath: relativePath, kind: .changedDuringScan))
            return
        }
        guard seenFiles.insert(FileKey(before)).inserted else { return }

        let allocated = before.st_blocks >= 0 ? UInt64(before.st_blocks) * 512 : nil
        candidates.append(AnalysisCandidate(
            category: rule.category,
            url: url,
            relativePath: relativePath,
            logicalBytes: UInt64(before.st_size),
            allocatedBytes: allocated,
            modifiedAt: modifiedAt,
            reason: rule.reason,
            confidence: .conservative,
            identity: FileIdentity(
                device: UInt64(before.st_dev), inode: UInt64(before.st_ino),
                modifiedSeconds: Int64(before.st_mtimespec.tv_sec),
                modifiedNanoseconds: Int64(before.st_mtimespec.tv_nsec),
                changedSeconds: Int64(before.st_ctimespec.tv_sec),
                changedNanoseconds: Int64(before.st_ctimespec.tv_nsec),
                mode: before.st_mode,
                logicalBytes: UInt64(before.st_size)
            ),
            isSelected: false
        ))
        let sum = foundLogicalBytes.addingReportingOverflow(UInt64(before.st_size))
        foundLogicalBytes = sum.overflow ? UInt64.max : sum.partialValue
        reportProgress(for: rule.category)
    }

    private func reportProgress(for category: AnalysisCategory) {
        progress?(AnalysisProgress(
            category: category,
            scannedEntries: scannedEntries,
            foundItems: candidates.count,
            foundLogicalBytes: foundLogicalBytes,
            issueCount: issues.count
        ))
    }
}

private struct FileKey: Hashable {
    let device: dev_t
    let inode: ino_t

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
    }
}

enum ScanError: LocalizedError {
    case cannotOpenHome

    var errorDescription: String? {
        switch self {
        case .cannotOpenHome: "Não foi possível abrir a pasta de análise."
        }
    }
}
