import Foundation

enum AnalysisCategory: String, CaseIterable, Codable, Sendable {
    case oldLogs
    case crashReports
    case userCaches
    case oldInstallers

    var title: String {
        switch self {
        case .oldLogs: "Logs antigos"
        case .crashReports: "Relatórios de falha"
        case .userCaches: "Caches de aplicativos"
        case .oldInstallers: "Instaladores antigos"
        }
    }
}

enum CandidateConfidence: String, Codable, Sendable {
    case conservative
}

struct FileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
    let mode: UInt16
    let logicalBytes: UInt64
}

struct AnalysisCandidate: Identifiable, Sendable {
    let category: AnalysisCategory
    let url: URL
    let relativePath: String
    let logicalBytes: UInt64
    let allocatedBytes: UInt64?
    let modifiedAt: Date
    let reason: String
    let confidence: CandidateConfidence
    let identity: FileIdentity
    var isSelected: Bool

    var id: String { relativePath }
}

enum AnalysisIssueKind: String, Sendable {
    case inaccessible
    case changedDuringScan
    case busy
    case depthLimit
    case readFailed
}

struct AnalysisIssue: Sendable {
    let relativePath: String
    let kind: AnalysisIssueKind
}

struct AnalysisProgress: Sendable {
    let category: AnalysisCategory
    let scannedEntries: Int
    let foundItems: Int
    let foundLogicalBytes: UInt64
    let issueCount: Int
}

struct AnalysisGroup: Sendable {
    let category: AnalysisCategory
    let candidates: [AnalysisCandidate]

    var logicalBytes: UInt64 {
        candidates.reduce(0) { $0.addingReportingOverflow($1.logicalBytes).overflow ? UInt64.max : $0 + $1.logicalBytes }
    }

    var selectedBytes: UInt64 {
        candidates.filter(\.isSelected).reduce(0) { $0.addingReportingOverflow($1.logicalBytes).overflow ? UInt64.max : $0 + $1.logicalBytes }
    }
}

struct AnalysisResult: Sendable {
    let scannedAt: Date
    let candidates: [AnalysisCandidate]
    let issues: [AnalysisIssue]

    var groups: [AnalysisGroup] {
        AnalysisCategory.allCases.compactMap { category in
            let items = candidates.filter { $0.category == category }
            return items.isEmpty ? nil : AnalysisGroup(category: category, candidates: items)
        }
    }

    var foundBytes: UInt64 {
        groups.reduce(0) { $0.addingReportingOverflow($1.logicalBytes).overflow ? UInt64.max : $0 + $1.logicalBytes }
    }

    var selectedBytes: UInt64 {
        groups.reduce(0) { $0.addingReportingOverflow($1.selectedBytes).overflow ? UInt64.max : $0 + $1.selectedBytes }
    }
}
