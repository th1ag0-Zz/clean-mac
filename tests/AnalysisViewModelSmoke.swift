import Foundation

@MainActor
@main
struct AnalysisViewModelSmoke {
    static func main() async throws {
        let suiteName = "cleanup-mac-interface-smoke-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Não foi possível criar preferências de teste")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let engine = AnalysisEngine(exclusions: AnalysisExclusions(defaults: defaults))
        let model = AnalysisViewModel(engine: engine,
                                      cleanupEngine: CleanupEngine(exclusions: AnalysisExclusions(defaults: defaults)))
        precondition(model.state == .initial)
        model.startAnalysis()
        precondition(model.state == .scanning)

        for _ in 0..<100 where model.state == .scanning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(model.state == .results)
        guard let result = model.result else { fatalError("Resultado ausente") }
        precondition(result.candidates.count == 6)
        precondition(model.selectedPaths.isEmpty)

        model.setSelected(true, for: result.candidates[0])
        precondition(model.selectedCandidates.count == 1)
        precondition(model.selectedBytes == result.candidates[0].logicalBytes)
        model.setSelected(false, for: result.candidates[0])
        precondition(model.selectedBytes == 0)

        model.setSelected(true, for: result.groups[0])
        precondition(model.selectedCandidates.count == result.groups[0].candidates.count)
        model.startAnalysis()
        for _ in 0..<100 where model.state == .scanning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(model.state == .results)
        precondition(model.selectedPaths.isEmpty)
        let home = try ScanScope.homeDirectory()
        let testLog = home.appendingPathComponent("Library/Logs/ui-smoke-\(UUID().uuidString).log")
        try Data("ui smoke\n".utf8).write(to: testLog)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -40 * 86_400)],
            ofItemAtPath: testLog.path
        )
        defer {
            if let destination = model.cleanupReport?.outcomes.first?.destination {
                try? FileManager.default.moveItem(at: destination, to: testLog)
            }
            try? FileManager.default.removeItem(at: testLog)
        }
        model.startAnalysis()
        for _ in 0..<100 where model.state == .scanning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let item = model.result?.candidates.first(where: { $0.url == testLog }) else {
            fatalError("Log de interface ausente")
        }
        model.setSelected(true, for: item)
        model.performCleanup()
        for _ in 0..<100 where model.state == .cleaning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(model.state == .completed && model.cleanupReport?.movedCount == 1)
        model.scanTrash()
        for _ in 0..<100 where model.trashState == .loading {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(model.trashState == .ready)
        precondition(model.trashSnapshot?.items.contains(where: {
            $0.url == model.cleanupReport?.outcomes.first?.destination
        }) == true)
        print("OK: estados, seleção, análise, limpeza confirmada e inspeção da Lixeira")
    }
}
