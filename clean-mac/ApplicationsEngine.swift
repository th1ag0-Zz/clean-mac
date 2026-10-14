import AppKit
import Darwin
import Foundation

struct ManagedApp: Identifiable, Sendable {
    let item: ManagedAppItem
    let name: String
    let bundleID: String
    let version: String
    let buildVersion: String
    let updateFeedURL: URL?
    let associated: [ManagedAppItem]
    var id: String { item.id }
}

struct ManagedAppItem: Identifiable, Sendable {
    enum Kind: Sendable { case app, data, residue }
    let kind: Kind
    let url: URL
    let root: URL
    let relativePath: String
    let bundleID: String
    let identity: AdvancedIdentity
    let infoIdentity: AdvancedIdentity?
    var id: String { url.path }
}

struct ApplicationsSnapshot: Sendable {
    let apps: [ManagedApp]
    let residues: [ManagedAppItem]
    let installerAnalysis: AnalysisResult
    var installers: [AnalysisCandidate] {
        installerAnalysis.candidates.filter { $0.category == .oldInstallers }
    }
}

struct ApplicationsOutcome: Identifiable, Sendable {
    let path: String
    let destination: URL?
    let error: String?
    var id: String { path }
    var succeeded: Bool { destination != nil && error == nil }
}

struct ApplicationsReport: Sendable {
    let outcomes: [ApplicationsOutcome]
    var succeededCount: Int { outcomes.filter(\.succeeded).count }
}

actor ApplicationsEngine {
    private let analysis = AnalysisEngine()
    private let cleanup = CleanupEngine()

    // Somente caminhos de usuário cujo último componente coincide com o bundle ID.
    private static let dataLocations: [([String], String)] = [
        (["Library", "Application Support"], ""),
        (["Library", "Caches"], ""),
        (["Library", "Containers"], ""),
        (["Library", "HTTPStorages"], ""),
        (["Library", "WebKit"], ""),
        (["Library", "Preferences"], ".plist"),
        (["Library", "Saved Application State"], ".savedState")
    ]

    func scan() async throws -> ApplicationsSnapshot {
        let home = try ScanScope.homeDirectory()
        let system = systemRoot(home: home)
        var apps: [ManagedApp] = []
        var ids: [String: Int] = [:]
        for (root, path) in [(system, "Applications"), (home, "Applications")] {
            let folder = root.appendingPathComponent(path, isDirectory: true)
            for url in contents(of: folder) where url.pathExtension.lowercased() == "app" {
                try Task.checkCancellation()
                guard let item = makeItem(url, root: root, bundleID: "", kind: .app),
                      item.identity.mode & S_IFMT == S_IFDIR,
                      let bundle = Bundle(url: url),
                      let id = bundle.bundleIdentifier, validID(id),
                      !id.hasPrefix("com.apple."),
                      id != Bundle.main.bundleIdentifier,
                      let infoIdentity = appInfoIdentity(url) else { continue }
                let appItem = ManagedAppItem(kind: .app, url: url, root: root,
                                             relativePath: item.relativePath, bundleID: id,
                                             identity: item.identity, infoIdentity: infoIdentity)
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
                let buildVersion = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? version
                let feed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)
                    .flatMap(URL.init(string:))
                let updateFeedURL = feed?.scheme?.lowercased() == "https" ? feed : nil
                apps.append(ManagedApp(item: appItem, name: name, bundleID: id,
                                       version: version, buildVersion: buildVersion,
                                       updateFeedURL: updateFeedURL, associated: []))
                ids[id, default: 0] += 1
            }
        }
        apps = apps.map { app in
            let associated = ids[app.bundleID] == 1
                ? associatedItems(bundleID: app.bundleID, home: home, kind: .data) : []
            return ManagedApp(item: app.item, name: app.name, bundleID: app.bundleID,
                              version: app.version, buildVersion: app.buildVersion,
                              updateFeedURL: app.updateFeedURL, associated: associated)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var residues: [ManagedAppItem] = []
        for (components, suffix) in Self.dataLocations {
            let folder = home.appendingPathComponent(components.joined(separator: "/"), isDirectory: true)
            for url in contents(of: folder) where url.lastPathComponent.hasSuffix(suffix) {
                try Task.checkCancellation()
                let name = url.lastPathComponent
                let id = suffix.isEmpty ? name : String(name.dropLast(suffix.count))
                guard validID(id), ids[id] == nil,
                      NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).isEmpty,
                      let item = makeItem(url, root: home, bundleID: id, kind: .residue) else { continue }
                residues.append(item)
            }
        }
        residues.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        return ApplicationsSnapshot(apps: apps, residues: residues,
                                    installerAnalysis: try await analysis.analyze())
    }

    func execute(_ snapshot: ApplicationsSnapshot, appIDs: Set<String>,
                 dataIDs: Set<String>, residueIDs: Set<String>, installerIDs: Set<String>) async throws -> ApplicationsReport {
        let apps = snapshot.apps.filter { appIDs.contains($0.id) }
        let allData = snapshot.apps.flatMap(\.associated)
        let data = allData.filter { dataIDs.contains($0.id) }
        let residues = snapshot.residues.filter { residueIDs.contains($0.id) }
        guard apps.count == appIDs.count, data.count == dataIDs.count,
              residues.count == residueIDs.count,
              Set(snapshot.installers.map(\.id)).isSuperset(of: installerIDs),
              data.allSatisfy({ item in apps.contains { $0.bundleID == item.bundleID } }),
              !appIDs.isEmpty || !dataIDs.isEmpty || !residueIDs.isEmpty || !installerIDs.isEmpty else {
            throw ApplicationsError.invalidSelection
        }
        let installerPlan = installerIDs.isEmpty ? nil :
            try await cleanup.makePlan(from: snapshot.installerAnalysis, selectedPaths: installerIDs)
        var outcomes: [ApplicationsOutcome] = []
        for app in apps {
            try Task.checkCancellation()
            outcomes.append(move(app.item))
        }
        for item in data {
            try Task.checkCancellation()
            let owners = apps.filter { $0.bundleID == item.bundleID }
            if owners.allSatisfy({ app in outcomes.contains { $0.path == app.item.url.path && $0.succeeded } }) {
                outcomes.append(move(item))
            } else {
                outcomes.append(ApplicationsOutcome(path: item.url.path, destination: nil,
                    error: "O aplicativo não foi movido; os dados foram preservados."))
            }
        }
        for item in residues {
            try Task.checkCancellation()
            outcomes.append(move(item))
        }
        if let installerPlan {
            let report = try await cleanup.execute(installerPlan)
            outcomes += report.outcomes.map {
                ApplicationsOutcome(path: $0.candidate.url.path, destination: $0.destination,
                                    error: $0.error)
            }
        }
        return ApplicationsReport(outcomes: outcomes)
    }

    private func associatedItems(bundleID: String, home: URL, kind: ManagedAppItem.Kind) -> [ManagedAppItem] {
        Self.dataLocations.compactMap { components, suffix in
            let url = home.appendingPathComponent((components + [bundleID + suffix]).joined(separator: "/"))
            return makeItem(url, root: home, bundleID: bundleID, kind: kind)
        }
    }

    private func move(_ item: ManagedAppItem) -> ApplicationsOutcome {
        do {
            let home = try ScanScope.homeDirectory()
            guard isAllowed(item, home: home),
                  item.kind != .app || !NSWorkspace.shared.runningApplications.contains(where: {
                      !$0.isTerminated && $0.bundleURL?.standardizedFileURL == item.url.standardizedFileURL
                  }) else { throw ApplicationsError.invalidSelection }
            let fd = try openValidated(item)
            defer { close(fd) }
            let destination: URL
            if ScanScope.isFixture {
            let trash = home.appendingPathComponent(".Trash", isDirectory: true)
            destination = trash.appendingPathComponent(UUID().uuidString + "-" + item.url.lastPathComponent)
            try FileManager.default.moveItem(at: item.url, to: destination)
            } else {
            var moved: NSURL?
            try FileManager.default.trashItem(at: item.url, resultingItemURL: &moved)
            guard let moved else { throw ApplicationsError.changed }
            destination = moved as URL
            }
            var info = stat()
            guard lstat(destination.path, &info) == 0,
                  info.st_dev == item.identity.device,
                  info.st_ino == item.identity.inode else { throw ApplicationsError.changed }
            return ApplicationsOutcome(path: item.url.path, destination: destination, error: nil)
        } catch {
            return ApplicationsOutcome(path: item.url.path, destination: nil,
                                       error: error.localizedDescription)
        }
    }

    private func isAllowed(_ item: ManagedAppItem, home: URL) -> Bool {
        guard validID(item.bundleID),
              item.url == item.root.appendingPathComponent(item.relativePath),
              !item.relativePath.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else { return false }
        switch item.kind {
        case .app:
            let system = systemRoot(home: home)
            guard (item.root == system || item.root == home),
                  item.url.deletingLastPathComponent() == item.root.appendingPathComponent("Applications"),
                  item.url.pathExtension.lowercased() == "app",
                  let expectedInfo = item.infoIdentity,
                  let currentInfo = appInfoIdentity(item.url),
                  expectedInfo.device == currentInfo.device,
                  expectedInfo.inode == currentInfo.inode,
                  expectedInfo.mode == currentInfo.mode,
                  expectedInfo.size == currentInfo.size,
                  expectedInfo.modifiedSeconds == currentInfo.modifiedSeconds,
                  expectedInfo.modifiedNanoseconds == currentInfo.modifiedNanoseconds,
                  expectedInfo.changedSeconds == currentInfo.changedSeconds,
                  expectedInfo.changedNanoseconds == currentInfo.changedNanoseconds,
                  let data = try? Data(contentsOf: item.url.appendingPathComponent("Contents/Info.plist")),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  plist["CFBundleIdentifier"] as? String == item.bundleID else { return false }
            return true
        case .data, .residue:
            guard item.root == home,
                  Self.dataLocations.contains(where: { components, suffix in
                      item.relativePath == (components + [item.bundleID + suffix]).joined(separator: "/")
                  }) else { return false }
            if item.kind == .residue {
                guard NSWorkspace.shared.urlsForApplications(withBundleIdentifier: item.bundleID).isEmpty else { return false }
            }
            return true
        }
    }

    private func openValidated(_ item: ManagedAppItem) throws -> Int32 {
        let parts = item.relativePath.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ApplicationsError.changed
        }
        var fd = open(item.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ApplicationsError.changed }
        var rootInfo = stat()
        guard fstat(fd, &rootInfo) == 0, rootInfo.st_dev == item.identity.device else {
            close(fd); throw ApplicationsError.changed
        }
        for part in parts.dropLast() {
            let next = part.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            close(fd)
            guard next >= 0 else { throw ApplicationsError.changed }
            var parentInfo = stat()
            guard fstat(next, &parentInfo) == 0, parentInfo.st_dev == rootInfo.st_dev else {
                close(next); throw ApplicationsError.changed
            }
            fd = next
        }
        var before = stat()
        guard parts.last!.withCString({ fstatat(fd, $0, &before, AT_SYMLINK_NOFOLLOW) }) == 0,
              item.identity.matches(before) else { close(fd); throw ApplicationsError.changed }
        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC |
            ((before.st_mode & S_IFMT) == S_IFDIR ? O_DIRECTORY : O_NONBLOCK)
        let opened = parts.last!.withCString { openat(fd, $0, flags) }
        close(fd)
        guard opened >= 0 else { throw ApplicationsError.changed }
        var after = stat()
        guard fstat(opened, &after) == 0, item.identity.matches(after) else {
            close(opened); throw ApplicationsError.changed
        }
        return opened
    }

    private func makeItem(_ url: URL, root: URL, bundleID: String,
                          kind: ManagedAppItem.Kind) -> ManagedAppItem? {
        var info = stat()
        var rootInfo = stat()
        guard lstat(url.path, &info) == 0,
              lstat(root.path, &rootInfo) == 0,
              info.st_dev == rootInfo.st_dev,
              info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFREG,
              url.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/") else { return nil }
        let relative = String(url.path.dropFirst(root.path == "/" ? 1 : root.path.count + 1))
        return ManagedAppItem(kind: kind, url: url, root: root, relativePath: relative,
                              bundleID: bundleID, identity: AdvancedIdentity(info), infoIdentity: nil)
    }

    private func appInfoIdentity(_ app: URL) -> AdvancedIdentity? {
        var contents = stat()
        var info = stat()
        guard lstat(app.appendingPathComponent("Contents").path, &contents) == 0,
              contents.st_mode & S_IFMT == S_IFDIR,
              lstat(app.appendingPathComponent("Contents/Info.plist").path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG else { return nil }
        return AdvancedIdentity(info)
    }

    private func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])) ?? []
    }

    private func validID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy({ !$0.isEmpty }) &&
            id.count <= 200 && !id.hasPrefix("com.apple.") &&
            id.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0)
            }
    }

    private func systemRoot(home: URL) -> URL {
        ScanScope.isFixture ? home.appendingPathComponent("SystemRoot", isDirectory: true) : URL(fileURLWithPath: "/", isDirectory: true)
    }
}

private enum ApplicationsError: LocalizedError {
    case invalidSelection, changed
    var errorDescription: String? {
        switch self {
        case .invalidSelection: "Seleção inválida ou aplicativo em execução. Analise novamente."
        case .changed: "O item mudou desde a análise. Analise novamente."
        }
    }
}
