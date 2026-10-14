import Foundation

private actor StageLog {
    var stages: [SmartCareStage] = []
    func append(_ stage: SmartCareStage) { stages.append(stage) }
}

@main
struct SmartCareSmoke {
    @MainActor
    static func main() async throws {
        precondition(ScanScope.isFixture, "Smart Care smoke must use the marked fixture")
        let log = StageLog()
        let snapshot = try await SmartCareEngine().scan { stage in await log.append(stage) }
        let stages = await log.stages
        precondition(stages == SmartCareStage.allCases, "All scan stages must be reported in order")
        let expectedIssues = snapshot.cleanupResult.issues.count + snapshot.advancedResult.issues.count +
            snapshot.organizationResult.inaccessibleLocations + snapshot.largeFilesResult.inaccessibleLocations +
            snapshot.applicationsResult.installerAnalysis.issues.count + (snapshot.protectionResult?.issues.count ?? 0) +
            (snapshot.protectionError == nil ? 0 : 1)
        precondition(snapshot.issues == expectedIssues, "Every engine's warnings must appear in Smart Care")
        precondition(snapshot.protectionResult != nil, "Fixture protection audit must finish")
        let model = SmartCareViewModel()
        model.scan()
        model.cancel()
        precondition(model.state == .idle)
        // A replaced task must not publish an old result or progress into the new run.
        model.scan()
        for _ in 0..<1500 where model.state == .scanning {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(model.state == .results, "Replacement scan must finish")
        precondition(model.stage == .complete)
        precondition(model.snapshot != nil)
        model.scan()
        model.cancel()
        try await Task.sleep(for: .milliseconds(300))
        precondition(model.state == .idle, "Cancelled task must not restore results")
        precondition(model.snapshot == nil)
        print("PASS: Smart Care stages, warning totals, cancellation and replacement scan")
    }
}
