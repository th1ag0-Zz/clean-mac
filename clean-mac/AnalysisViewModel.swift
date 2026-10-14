import AppKit
import Combine
import Foundation

enum AnalysisScreenState: Equatable {
    case initial
    case scanning
    case empty
    case results
    case cleaning
    case completed
    case failed
}

enum TrashScreenState: Equatable {
    case idle
    case loading
    case ready
    case emptying
    case finished
    case failed
}

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published private(set) var state: AnalysisScreenState = .initial
    @Published private(set) var result: AnalysisResult?
    @Published private(set) var progress: AnalysisProgress?
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var excludedPaths: Set<String> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var cleanupProgress: CleanupProgress?
    @Published private(set) var cleanupReport: CleanupReport?
    @Published private(set) var trashState: TrashScreenState = .idle
    @Published private(set) var trashSnapshot: TrashSnapshot?
    @Published private(set) var trashReport: TrashReport?
    @Published private(set) var trashError: String?

    private let engine: AnalysisEngine
    private let cleanupEngine: CleanupEngine
    private let trashEngine: TrashEngine
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()

    init(engine: AnalysisEngine = AnalysisEngine(),
         cleanupEngine: CleanupEngine = CleanupEngine(),
         trashEngine: TrashEngine = TrashEngine()) {
        self.engine = engine
        self.cleanupEngine = cleanupEngine
        self.trashEngine = trashEngine
    }

    private var restingState: AnalysisScreenState {
        guard let result else { return .initial }
        return result.candidates.isEmpty ? .empty : .results
    }

    var selectedCandidates: [AnalysisCandidate] {
        result?.candidates.filter { selectedPaths.contains($0.relativePath) } ?? []
    }

    var selectedBytes: UInt64 {
        selectedCandidates.reduce(0) { partial, candidate in
            let sum = partial.addingReportingOverflow(candidate.logicalBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }

    func accept(_ analysis: AnalysisResult) {
        scanTask?.cancel(); scanID = UUID()
        result = analysis; selectedPaths = []; cleanupReport = nil; errorMessage = nil
        state = analysis.candidates.isEmpty ? .empty : .results
        loadExclusions()
    }

    func loadExclusions() {
        Task { excludedPaths = await engine.excludedPaths() }
    }

    func startAnalysis() {
        scanTask?.cancel()
        scanID = UUID()
        let currentID = scanID
        progress = nil
        errorMessage = nil
        cleanupReport = nil
        state = .scanning

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let analysis = try await engine.analyze { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.scanID == currentID,
                              self.state == .scanning else { return }
                        self.progress = update
                    }
                }
                guard scanID == currentID else { return }
                result = analysis
                selectedPaths = []
                excludedPaths = await engine.excludedPaths()
                state = analysis.candidates.isEmpty ? .empty : .results
            } catch is CancellationError {
                guard scanID == currentID else { return }
                state = restingState
            } catch {
                guard scanID == currentID else { return }
                errorMessage = error.localizedDescription
                state = .failed
            }
        }
    }

    func cancelAnalysis() {
        scanTask?.cancel()
        scanID = UUID()
        state = restingState
    }

    func setSelected(_ selected: Bool, for candidate: AnalysisCandidate) {
        if selected { selectedPaths.insert(candidate.relativePath) }
        else { selectedPaths.remove(candidate.relativePath) }
    }

    func setSelected(_ selected: Bool, for group: AnalysisGroup) {
        for candidate in group.candidates {
            setSelected(selected, for: candidate)
        }
    }

    func exclude(_ candidate: AnalysisCandidate) {
        Task {
            await engine.exclude(candidate)
            startAnalysis()
        }
    }

    func include(_ relativePath: String) {
        Task {
            await engine.include(relativePath: relativePath)
            startAnalysis()
        }
    }

    func showInFinder(_ candidate: AnalysisCandidate) {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
    }

    func performCleanup() {
        guard let result, !selectedPaths.isEmpty else { return }
        cleanupProgress = nil
        cleanupReport = nil
        errorMessage = nil
        state = .cleaning
        let selection = selectedPaths
        Task { [self] in
            do {
                let plan = try await cleanupEngine.makePlan(from: result, selectedPaths: selection)
                let report = try await cleanupEngine.execute(plan) { [weak self] update in
                    Task { @MainActor [weak self] in self?.cleanupProgress = update }
                }
                cleanupReport = report
                state = .completed
            } catch {
                errorMessage = error.localizedDescription
                state = .failed
            }
        }
    }

    func scanTrash() {
        trashState = .loading
        trashError = nil
        Task {
            do {
                trashSnapshot = try await trashEngine.inspect()
                trashState = .ready
            } catch {
                trashError = error.localizedDescription
                trashState = .failed
            }
        }
    }

    func emptyTrash() {
        guard let snapshot = trashSnapshot, !snapshot.items.isEmpty else { return }
        trashState = .emptying
        trashError = nil
        Task {
            do {
                trashReport = try await trashEngine.empty(snapshot)
                trashState = .finished
            } catch {
                trashError = error.localizedDescription
                trashState = .failed
            }
        }
    }
}
