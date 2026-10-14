import Foundation

/// Guarda caminhos relativos à home. O motor valida o caminho antes de consultá-lo.
final class AnalysisExclusions {
    private let defaults: UserDefaults
    private let key = "analysis.excludedRelativePaths.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func exclude(_ relativePath: String) {
        guard Self.isValid(relativePath) else { return }
        var paths = all()
        paths.insert(relativePath)
        defaults.set(paths.sorted(), forKey: key)
    }

    func include(_ relativePath: String) {
        var paths = all()
        paths.remove(relativePath)
        defaults.set(paths.sorted(), forKey: key)
    }

    private static func isValid(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") &&
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}
