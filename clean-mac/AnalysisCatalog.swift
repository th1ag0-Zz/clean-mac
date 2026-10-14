import Foundation

struct AnalysisRule: Sendable {
    let category: AnalysisCategory
    let directoryComponents: [String]
    let minimumAge: TimeInterval
    let allowedExtensions: Set<String>?
    let reason: String
    let recursive: Bool

    init(category: AnalysisCategory, directoryComponents: [String], minimumAge: TimeInterval,
         allowedExtensions: Set<String>?, reason: String, recursive: Bool = true) {
        self.category = category
        self.directoryComponents = directoryComponents
        self.minimumAge = minimumAge
        self.allowedExtensions = allowedExtensions
        self.reason = reason
        self.recursive = recursive
    }

    func accepts(fileName: String, modifiedAt: Date, now: Date) -> Bool {
        guard modifiedAt <= now.addingTimeInterval(-minimumAge) else { return false }
        guard let allowedExtensions else { return true }
        return allowedExtensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased())
    }
}

enum AnalysisCatalog {
    static let rules: [AnalysisRule] = [
        AnalysisRule(
            category: .oldLogs,
            directoryComponents: ["Library", "Logs"],
            minimumAge: 30 * 24 * 60 * 60,
            allowedExtensions: ["log"],
            reason: "Arquivo de log sem alterações há pelo menos 30 dias."
        ),
        AnalysisRule(
            category: .crashReports,
            directoryComponents: ["Library", "Logs", "DiagnosticReports"],
            minimumAge: 30 * 24 * 60 * 60,
            allowedExtensions: ["ips", "crash", "diag"],
            reason: "Relatório de falha sem alterações há pelo menos 30 dias."
        ),
        AnalysisRule(
            category: .userCaches,
            directoryComponents: ["Library", "Caches"],
            minimumAge: 30 * 24 * 60 * 60,
            allowedExtensions: nil,
            reason: "Arquivo em cache do usuário sem alterações há pelo menos 30 dias. O aplicativo pode recriá-lo."
        ),
        AnalysisRule(
            category: .oldInstallers,
            directoryComponents: ["Downloads"],
            minimumAge: 30 * 24 * 60 * 60,
            allowedExtensions: ["dmg", "pkg"],
            reason: "Instalador sem alterações há pelo menos 30 dias. Confirme se ainda precisa dele.",
            recursive: false
        )
    ]
}
