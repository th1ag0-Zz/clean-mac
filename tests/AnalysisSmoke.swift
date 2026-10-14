import Foundation

@main
struct AnalysisSmoke {
    static func main() async throws {
        let suiteName = "cleanup-mac-analysis-smoke-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Não foi possível criar preferências de teste")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let engine = AnalysisEngine(exclusions: AnalysisExclusions(defaults: defaults))
        let initial = try await engine.analyze()
        let paths = Set(initial.candidates.map(\.relativePath))
        let oldLog = "Library/Logs/old.log"
        let ownCache = "Library/Caches/CleanupMac/Regenerable/cache.bin"
        let otherCache = "Library/Caches/UnknownApp/state.bin"
        let recognizedCache = "Library/Caches/RecognizedApp/cache.bin"
        let crashReport = "Library/Logs/DiagnosticReports/old.ips"
        let installer = "Downloads/old-installer.dmg"
        let expected = Set([oldLog, ownCache, otherCache, recognizedCache, crashReport, installer])
        precondition(paths == expected, "Resultados inesperados: \(paths)")
        precondition(initial.groups.count == 4)
        precondition(initial.candidates.first(where: { $0.relativePath == installer })?.category == .oldInstallers)
        precondition(initial.selectedBytes == 0)
        precondition(initial.foundBytes == initial.candidates.reduce(0) { $0 + $1.logicalBytes })
        precondition(initial.candidates.allSatisfy { !$0.isSelected })

        guard let candidate = initial.candidates.first(where: { $0.relativePath == oldLog }) else {
            fatalError("Log antigo não encontrado")
        }
        await engine.exclude(candidate)
        let rescanned = try await engine.analyze()
        precondition(Set(rescanned.candidates.map(\.relativePath)) == expected.subtracting([oldLog]))

        let reopened = AnalysisEngine(exclusions: AnalysisExclusions(defaults: defaults))
        let persistedExclusions = await reopened.excludedPaths()
        precondition(persistedExclusions.contains(oldLog))
        await reopened.include(relativePath: oldLog)
        let restored = try await reopened.analyze()
        precondition(Set(restored.candidates.map(\.relativePath)) == paths)

        await reopened.exclude(relativePath: "Library/Logs")
        let withoutLogs = try await reopened.analyze()
        precondition(Set(withoutLogs.candidates.map(\.relativePath)) == expected.filter { !$0.hasPrefix("Library/Logs/") })
        await reopened.include(relativePath: "Library/Logs")

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reopened.analyze()
        }
        do {
            _ = try await cancelled.value
            fatalError("A análise cancelada deveria lançar CancellationError")
        } catch is CancellationError {
            print("OK: catálogo, segurança, totais, exclusões, nova análise e cancelamento")
        }
    }
}
