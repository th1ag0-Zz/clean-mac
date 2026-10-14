import Foundation

private actor ProtectionWatchCounter {
    var count = 0
    func changed() { count += 1 }
}

@main
struct ProtectionMonitorSmoke {
    static func main() async throws {
        guard ScanScope.isFixture else { fatalError("Monitor tests require fixture mode and never watch real user files.") }
        let home = try ScanScope.homeDirectory()
        let root = home.appendingPathComponent("Downloads")
        let directory = root.appendingPathComponent("watcher-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = ProtectionWatchCounter()
        let monitor = try ProtectionFolderMonitor(root: root) { Task { await counter.changed() } }
        defer { monitor.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("fixture event".utf8).write(to: directory.appendingPathComponent("nested.txt"))
        var detected = false
        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 500_000_000)
            if await counter.count > 0 { detected = true; break }
        }
        precondition(detected, "FSEvents callback expected for fixture file creation")
        let first = await counter.count
        try Data("changed nested content".utf8).write(to: directory.appendingPathComponent("nested.txt"))
        var nestedDetected = false
        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 500_000_000)
            if await counter.count > first { nestedDetected = true; break }
        }
        precondition(nestedDetected, "Existing files in descendant folders must be monitored")
        monitor.stop()
        try await Task.sleep(nanoseconds: 300_000_000)
        let afterStop = await counter.count
        try Data("after stop".utf8).write(to: directory.appendingPathComponent("after-stop.txt"))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let final = await counter.count
        precondition(final == afterStop, "Stopped watcher must not emit new callbacks")
        print("OK: recursive fixture file events and no callbacks after stream stop")
    }
}
