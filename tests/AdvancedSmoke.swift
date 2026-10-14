import Darwin
import Foundation

@main
struct AdvancedSmoke {
    static func main() async throws {
        let home = try ScanScope.homeDirectory()
        let fm = FileManager.default
        let token = UUID().uuidString
        let base = "advanced-\(token)"
        let filePaths = [
            "SystemRoot/Library/Caches/\(base).bin": AdvancedCategory.systemCaches,
            "SystemRoot/private/var/tmp/\(base).tmp": .systemCaches,
            "SystemRoot/Library/Logs/\(base).log": .systemLogs,
            "SystemRoot/private/var/log/\(base).log": .systemLogs,
            "Library/Containers/com.apple.mail/Data/Library/Mail Downloads/\(base).pdf": .mailDownloads
        ]
        let xcode = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/\(base)")
        let backup = home.appendingPathComponent("Library/Application Support/MobileSync/Backup/\(base)")
        let app = home.appendingPathComponent("SystemRoot/Applications/\(base).app")
        let language = app.appendingPathComponent("Contents/Resources/zz.lproj")
        let volume = home.appendingPathComponent("ExternalVolumes/\(base)/.Trashes/\(getuid())")
        let volumeItem = volume.appendingPathComponent("external.txt")
        let document = home.appendingPathComponent("Documents/\(base).txt")
        let files = filePaths.keys.map { home.appendingPathComponent($0) }
        defer {
            for url in files + [xcode, backup, app, document, home.appendingPathComponent("ExternalVolumes/\(base)")] {
                try? fm.removeItem(at: url)
            }
        }
        for url in files {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url)
            try oldDate(url)
        }
        for directory in [xcode, backup, language] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = directory.appendingPathComponent("data.bin")
            try Data("fixture".utf8).write(to: data)
            try oldDate(data)
        }
        let en = app.appendingPathComponent("Contents/Resources/en.lproj")
        try fm.createDirectory(at: en, withIntermediateDirectories: true)
        let info = app.appendingPathComponent("Contents/Info.plist")
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleDevelopmentRegion": "en", "CFBundleIdentifier": "test.advanced.\(token)"],
            format: .xml, options: 0)
        try infoData.write(to: info)
        try Data("versão atual".utf8).write(to: document)
        var coordinationError: NSError?
        var versionError: Error?
        NSFileCoordinator().coordinate(writingItemAt: document, options: [], error: &coordinationError) { url in
            do { _ = try NSFileVersion.addOfItem(at: url, withContentsOf: url) }
            catch { versionError = error }
        }
        if let error = coordinationError ?? versionError as NSError? { throw error }
        let engine = AdvancedCleanupEngine()
        let result = try await engine.analyze()
        let expected = Set(filePaths.values).union([.xcode, .deviceBackups, .documentVersions])
        let actual = Set(result.candidates.filter { $0.url.path.contains(base) }.map(\.category))
        precondition(actual == expected, "Categorias ausentes: \(expected.subtracting(actual))")
        precondition(result.candidates.allSatisfy { !$0.url.path.hasPrefix(app.path) })
        precondition(result.candidates.allSatisfy { !$0.url.path.contains("Documents/keep.txt") })
        guard let versionItem = result.candidates.first(where: { $0.url == document }) else {
            fatalError("Versão anterior ausente")
        }

        let selected = result.candidates.filter {
            $0.url.path.contains(base) && $0.category != .documentVersions
        }
        precondition(selected.count == 7)
        let changed = files.first { $0.path.contains("Mail Downloads") }!
        try Data("alterado".utf8).write(to: changed)
        let report = try await engine.execute(result, selectedIDs: Set(selected.map(\.id)))
        precondition(report.succeededCount == 6 && report.outcomes.count == 7)
        precondition(fm.fileExists(atPath: changed.path))
        for outcome in report.outcomes where outcome.succeeded {
            guard let destination = outcome.destination else { fatalError("Destino ausente") }
            try fm.moveItem(at: destination, to: outcome.candidate.url)
        }
        let versionReport = try await engine.execute(result, selectedIDs: [versionItem.id])
        precondition(versionReport.succeededCount == 1)
        let currentContents = try String(contentsOf: document, encoding: .utf8)
        precondition(currentContents == "versão atual")
        precondition((NSFileVersion.otherVersionsOfItem(at: document) ?? []).isEmpty)

        try fm.createDirectory(at: volume, withIntermediateDirectories: true)
        try Data("external".utf8).write(to: volumeItem)
        let trashEngine = TrashEngine()
        let snapshot = try await trashEngine.inspect()
        guard let item = snapshot.items.first(where: { $0.url == volumeItem }) else {
            fatalError("Lixeira do volume externo ausente")
        }
        let subset = TrashSnapshot(home: snapshot.home, rootIdentity: snapshot.rootIdentity,
                                   externalRoots: snapshot.externalRoots, items: [item], issues: [])
        let emptied = try await trashEngine.empty(subset)
        precondition(emptied.deletedCount == 1 && !fm.fileExists(atPath: volumeItem.path))
        print("OK: sistema, Xcode, Mail, backups, versões e Lixeira externa")
    }

    private static func oldDate(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -40 * 86_400)], ofItemAtPath: url.path)
    }
}
