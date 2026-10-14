import Foundation

@main struct AdditionalCleanupSmoke {
    static func main() async throws {
        precondition(ScanScope.isFixture)
        let home = try ScanScope.homeDirectory()
        let token = UUID().uuidString
        let fm = FileManager.default
        let model = home.appendingPathComponent(".lmstudio/models/fixture-\(token)")
        let broken = home.appendingPathComponent("Library/Preferences/fixture-\(token).plist")
        let valid = home.appendingPathComponent("Library/Preferences/valid-\(token).plist")
        let recent = home.appendingPathComponent("Library/Preferences/recent-\(token).plist")
        defer { for item in [model, broken, valid, recent] { try? fm.removeItem(at: item) } }
        try fm.createDirectory(at: model, withIntermediateDirectories: true)
        try Data(repeating: 42, count: 4096).write(to: model.appendingPathComponent("weights.gguf"))
        try fm.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken plist payload".utf8).write(to: broken)
        try Data("recent broken payload".utf8).write(to: recent)
        try PropertyListSerialization.data(fromPropertyList: ["key": "value"], format: .binary, options: 0).write(to: valid)
        for item in [broken, valid] {
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -45 * 86400)], ofItemAtPath: item.path)
        }
        let engine = AdvancedCleanupEngine()
        let result = try await engine.analyze()
        guard let modelCandidate = result.candidates.first(where: { $0.url.path == model.path }),
              let brokenCandidate = result.candidates.first(where: { $0.url.path == broken.path }) else { fatalError("Additional cleanup candidates absent") }
        precondition(modelCandidate.category == .aiModels && modelCandidate.logicalBytes == 4096)
        precondition(brokenCandidate.category == .brokenPreferences)
        precondition(!result.candidates.contains(where: { $0.url.path == valid.path || $0.url.path == recent.path }))
        let report = try await engine.execute(result, selectedIDs: [modelCandidate.id, brokenCandidate.id])
        precondition(report.succeededCount == 2 && fm.fileExists(atPath: valid.path) && fm.fileExists(atPath: recent.path))
        for outcome in report.outcomes { if let destination = outcome.destination { try fm.moveItem(at: destination, to: outcome.candidate.url) } }
        print("OK: local model inventory, malformed vs valid/recent plist, reviewed fixture Trash, sibling preservation")
    }
}
