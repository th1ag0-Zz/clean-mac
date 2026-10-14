import Foundation

/// Resolves the real home or explicitly validated, project-local test fixture.
enum ScanScope {
    static var isFixture: Bool { ProcessInfo.processInfo.environment["CLEANUP_MAC_FIXTURE_HOME"] != nil }
    static func homeDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["CLEANUP_MAC_FIXTURE_HOME"] else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        guard !path.isEmpty else { throw ScanScopeError.invalidFixture }

        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let expectedRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".fixtures/sample-home", isDirectory: true)
            .standardizedFileURL
        guard root == expectedRoot else {
            throw ScanScopeError.invalidFixture
        }

        let marker = root.appendingPathComponent(".cleanup-mac-fixture", isDirectory: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
        let parentValues = try root.deletingLastPathComponent()
            .resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true,
              parentValues.isSymbolicLink != true,
              attributes[.type] as? FileAttributeType == .typeDirectory,
              root.lastPathComponent == "sample-home",
              try String(contentsOf: marker, encoding: .utf8) == "cleanup-mac-test-home-v1\n" else {
            throw ScanScopeError.invalidFixture
        }
        return root
    }
}

enum ScanScopeError: LocalizedError {
    case invalidFixture

    var errorDescription: String? {
        switch self {
        case .invalidFixture:
            return "A pasta de teste não é uma home de fixture válida."
        }
    }
}
