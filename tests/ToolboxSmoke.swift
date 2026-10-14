import AppKit
import SQLite3

@main
struct ToolboxSmoke {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    @MainActor
    static func main() async throws {
        let originalFixture = ProcessInfo.processInfo.environment["CLEANUP_MAC_FIXTURE_HOME"]
        let root = originalFixture.map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("cleanmac-toolbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        setenv("CLEANUP_MAC_FIXTURE_HOME", directory.path, 1)
        defer {
            if let originalFixture { setenv("CLEANUP_MAC_FIXTURE_HOME", originalFixture, 1) }
            else { unsetenv("CLEANUP_MAC_FIXTURE_HOME") }
        }
        let file = directory.appendingPathComponent("selected.txt")
        let sibling = directory.appendingPathComponent("keep.txt")
        try Data("delete".utf8).write(to: file)
        try Data("keep".utf8).write(to: sibling)
        let selected = try PermanentDeletion.inspect(file)
        let outcome = PermanentDeletion.remove([selected])
        check(outcome.deletedIDs == [selected.id] && outcome.errors.isEmpty, "Selected file deletion")
        check(FileManager.default.fileExists(atPath: sibling.path), "Sibling preserved")
        try Data("initial".utf8).write(to: file)
        let stale = try PermanentDeletion.inspect(file)
        try Data("changed content".utf8).write(to: file)
        check(PermanentDeletion.remove([stale]).deletedIDs.isEmpty, "Changed file rejected")
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sibling)
        do { _ = try PermanentDeletion.inspect(link); fatalError("Symlink accepted") } catch {}
        do { _ = try PermanentDeletion.inspect(directory); fatalError("Directory accepted") } catch {}
        do { _ = try PermanentDeletion.inspect(URL(fileURLWithPath: "/etc/hosts")); fatalError("Outside fixture path accepted") } catch {}
        let ancestor = directory.appendingPathComponent("ancestor", isDirectory: true)
        try FileManager.default.createDirectory(at: ancestor, withIntermediateDirectories: false)
        let victim = ancestor.appendingPathComponent("victim.txt")
        try Data("preserve through replacement".utf8).write(to: victim)
        let beforeReplacement = try PermanentDeletion.inspect(victim)
        let savedAncestor = directory.appendingPathComponent("ancestor-original", isDirectory: true)
        try FileManager.default.moveItem(at: ancestor, to: savedAncestor)
        try FileManager.default.createSymbolicLink(at: ancestor, withDestinationURL: savedAncestor)
        do { _ = try PermanentDeletion.inspect(victim); fatalError("Ancestor symlink accepted") } catch {}
        check(PermanentDeletion.remove([beforeReplacement]).deletedIDs.isEmpty, "Ancestor symlink replacement rejected")
        check(FileManager.default.fileExists(atPath: savedAncestor.appendingPathComponent("victim.txt").path), "Ancestor symlink target preserved")
        try FileManager.default.removeItem(at: ancestor)
        try FileManager.default.createDirectory(at: ancestor, withIntermediateDirectories: false)
        try FileManager.default.linkItem(at: savedAncestor.appendingPathComponent("victim.txt"), to: victim)
        check(PermanentDeletion.remove([beforeReplacement]).deletedIDs.isEmpty, "Replacement parent with same hardlinked inode rejected")
        check(FileManager.default.fileExists(atPath: victim.path), "Replacement parent's file preserved")
        check(SnapshotName.date(from: "com.apple.TimeMachine.2026-10-14-120000.local") == "2026-10-14-120000", "Snapshot date parsed")
        check(SnapshotName.date(from: "com.apple.TimeMachine.2026-10-14-120000;id.local") == nil, "Snapshot injection rejected")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>system-entities</key><array><dict><key>dev-entry</key><string>/dev/disk9s1</string><key>mount-point</key><string>/Volumes/Test</string></dict></array></dict></plist>
        """
        check(MountedImage.parse(plist).first?.device == "/dev/disk9s1", "Mount plist parsed")
        let dbURL = directory.appendingPathComponent("index.sqlite")
        let backupURL = directory.appendingPathComponent("backup.sqlite")
        var db: OpaquePointer?
        check(sqlite3_open(dbURL.path, &db) == SQLITE_OK, "Create fixture database")
        check(sqlite3_exec(db, "CREATE TABLE messages(id INTEGER PRIMARY KEY, subject TEXT); INSERT INTO messages(subject) VALUES ('keep me');", nil, nil, nil) == SQLITE_OK, "Fixture data")
        sqlite3_close(db)
        _ = try MailIndexOptimizer.optimizeDatabase(at: dbURL, backupURL: backupURL)
        for url in [dbURL, backupURL] {
            db = nil
            check(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, "Open preserved database")
            var statement: OpaquePointer?
            check(sqlite3_prepare_v2(db, "SELECT subject FROM messages", -1, &statement, nil) == SQLITE_OK, "Read fixture row")
            check(sqlite3_step(statement) == SQLITE_ROW, "Row preserved")
            check(String(cString: sqlite3_column_text(statement, 0)) == "keep me", "Message data unchanged")
            sqlite3_finalize(statement)
            sqlite3_close(db)
        }
        let health = SystemHealth()
        health.start()
        try await Task.sleep(for: .milliseconds(2300))
        check(health.snapshot.memoryTotal > 0 && health.snapshot.diskTotal > 0 && health.snapshot.uptime > 0, "Real system metrics")
        check(health.snapshot.cpuUsage != nil, "CPU delta sampled")
        health.stop()
        print("Toolbox smoke passed: deletion safety, snapshots, disk-image parser, Mail index backup and real health sampling.")
    }
}
