import Foundation

@main
struct LargeFilesSmoke {
    static func main() async throws {
        let home = try ScanScope.homeDirectory()
        let root = home.appendingPathComponent("Documents/large-files-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func sparse(_ name: String, size: UInt64) throws -> URL {
            let url = root.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: size)
            try handle.close()
            return url
        }

        let large = try sparse("large.mov", size: 120 * 1_024 * 1_024)
        _ = try sparse("small.mov", size: 99 * 1_024 * 1_024)
        let package = root.appendingPathComponent("hidden.app", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let insidePackage = package.appendingPathComponent("inside.mov")
        FileManager.default.createFile(atPath: insidePackage.path, contents: nil)
        let packageHandle = try FileHandle(forWritingTo: insidePackage)
        try packageHandle.truncate(atOffset: 120 * 1_024 * 1_024)
        try packageHandle.close()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.mov"),
                                                   withDestinationURL: large)

        let result = try await LargeFilesEngine().scan()
        let ownFiles = result.files.filter { $0.url.path.hasPrefix(root.path + "/") }
        guard ownFiles.count == 1,
              ownFiles[0].url == large,
              ownFiles[0].logicalBytes == 120 * 1_024 * 1_024,
              ownFiles[0].allocatedBytes <= ownFiles[0].logicalBytes,
              result.scannedFiles >= 2 else {
            fatalError("Resultado inesperado: \(ownFiles.map(\.relativePath))")
        }
        print("OK: arquivos grandes, limite, links e pacotes")
    }
}
