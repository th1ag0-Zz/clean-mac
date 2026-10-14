import Foundation

struct CleanupPlan: Sendable {
    let home: URL
    let items: [AnalysisCandidate]
    let createdAt: Date

    var estimatedLogicalBytes: UInt64 {
        items.reduce(0) { partial, item in
            let sum = partial.addingReportingOverflow(item.logicalBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }
}

struct CleanupProgress: Sendable {
    let processed: Int
    let total: Int
    let currentPath: String
}

struct CleanupOutcome: Sendable, Identifiable {
    let candidate: AnalysisCandidate
    let destination: URL?
    let error: String?

    var id: String { candidate.relativePath }
    var moved: Bool { destination != nil && error == nil }
}

struct CleanupReport: Sendable {
    let outcomes: [CleanupOutcome]

    var movedCount: Int { outcomes.filter(\.moved).count }
    var failedCount: Int { outcomes.count - movedCount }
    var movedLogicalBytes: UInt64 {
        outcomes.filter(\.moved).reduce(0) { partial, outcome in
            let sum = partial.addingReportingOverflow(outcome.candidate.logicalBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }
    // Mover para a Lixeira não permite medir bytes efetivamente liberados.
    var freedBytes: UInt64? { nil }
}

enum CleanupError: LocalizedError {
    case emptySelection
    case unknownSelection
    case invalidPlan

    var errorDescription: String? {
        switch self {
        case .emptySelection: "Selecione pelo menos um item para limpar."
        case .unknownSelection: "A seleção contém um item fora dos resultados analisados."
        case .invalidPlan: "O plano de limpeza não corresponde à análise atual."
        }
    }
}
