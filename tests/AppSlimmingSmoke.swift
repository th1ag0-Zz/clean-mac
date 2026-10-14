import Foundation

@main
struct AppSlimmingSmoke {
    static func main() async throws {
        let manager = FileManager.default
        guard ScanScope.isFixture else { fatalError("Fixture required") }
        let home = try ScanScope.homeDirectory()
        let root = home.appendingPathComponent("Documents/app-slimming-smoke-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.c")
        try "int main(void) { return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
        let arm = root.appendingPathComponent("fixture-arm64")
        let intel = root.appendingPathComponent("fixture-x86_64")
        let universal = root.appendingPathComponent("fixture-universal")
        func run(_ executable: String, _ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        }
        try run("/usr/bin/xcrun", ["clang", "-arch", "arm64", source.path, "-o", arm.path])
        try run("/usr/bin/xcrun", ["clang", "-arch", "x86_64", source.path, "-o", intel.path])
        try run("/usr/bin/lipo", ["-create", arm.path, intel.path, "-output", universal.path])
        let app = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let executables = contents.appendingPathComponent("MacOS", isDirectory: true)
        let output = root.appendingPathComponent("Output", isDirectory: true)
        try manager.createDirectory(at: resources, withIntermediateDirectories: true)
        try manager.createDirectory(at: executables, withIntermediateDirectories: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        try manager.copyItem(at: universal, to: executables.appendingPathComponent("fixture"))
        let plist: [String: Any] = ["CFBundleExecutable": "fixture", "CFBundleIdentifier": "com.example.slimmingfixture", "CFBundleName": "Fixture", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleDevelopmentRegion": "de"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        for language in ["Base", "en", "de", "zz"] {
            let folder = resources.appendingPathComponent(language + ".lproj", isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data(repeating: 7, count: 50_000).write(to: folder.appendingPathComponent("resource.bin"))
        }
        let framework = contents.appendingPathComponent("Frameworks/Test.framework", isDirectory: true)
        let version = framework.appendingPathComponent("Versions/A", isDirectory: true)
        let frameworkResources = version.appendingPathComponent("Resources", isDirectory: true)
        try manager.createDirectory(at: frameworkResources, withIntermediateDirectories: true)
        try manager.copyItem(at: universal, to: version.appendingPathComponent("Test"))
        let frameworkPlist: [String: Any] = ["CFBundleExecutable": "Test", "CFBundleIdentifier": "com.example.slimmingfixture.framework", "CFBundlePackageType": "FMWK", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: frameworkPlist, format: .xml, options: 0).write(to: frameworkResources.appendingPathComponent("Info.plist"))
        try manager.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try manager.createSymbolicLink(atPath: framework.appendingPathComponent("Test").path, withDestinationPath: "Versions/Current/Test")
        try manager.createSymbolicLink(atPath: framework.appendingPathComponent("Resources").path, withDestinationPath: "Versions/Current/Resources")
        let originalBinary = try Data(contentsOf: executables.appendingPathComponent("fixture"))
        let engine = AppSlimmingEngine()
        let snapshot = try await engine.scan(app)
        precondition(snapshot.languages.first { $0.code == "Base" }?.mustKeep == true)
        precondition(snapshot.languages.first { $0.code == "en" }?.mustKeep == true)
        precondition(snapshot.languages.first { $0.code == "de" }?.mustKeep == true)
        precondition(snapshot.languages.first { $0.code == "zz" }?.logicalBytes == 50_000)
        precondition(snapshot.universalBinaries.count == 2)
        do {
            _ = try await engine.createCopy(snapshot, omitting: ["de"], thinArchitectures: false, outputFolder: output)
            fatalError("Development language accepted")
        } catch {}
        do {
            _ = try await engine.createCopy(snapshot, omitting: ["zz"], thinArchitectures: true, outputFolder: resources)
            fatalError("Output in source accepted")
        } catch {}
        let result = try await engine.createCopy(snapshot, omitting: ["zz"], thinArchitectures: true, outputFolder: output)
        precondition(result.removedLanguageCount == 1 && result.thinnedBinaryCount == 2 && result.savedBytes > 0)
        precondition(!manager.fileExists(atPath: result.copyURL.appendingPathComponent("Contents/Resources/zz.lproj").path))
        precondition(manager.fileExists(atPath: resources.appendingPathComponent("zz.lproj/resource.bin").path))
        let finalOriginalBinary = try Data(contentsOf: executables.appendingPathComponent("fixture"))
        precondition(finalOriginalBinary == originalBinary)
        let optimized = try await engine.scan(result.copyURL)
        precondition(optimized.binaries.count == 2 && optimized.binaries.allSatisfy { $0.architectures == [snapshot.nativeArchitecture] })
        precondition(optimized.languages.contains { $0.code == "de" })
        let linkedApp = root.appendingPathComponent("Linked.app")
        try manager.createSymbolicLink(at: linkedApp, withDestinationURL: app)
        do { _ = try await engine.scan(linkedApp); fatalError("Source app link accepted") } catch {}
        let unsafeLink = resources.appendingPathComponent("unsafe-link")
        try manager.createSymbolicLink(at: unsafeLink, withDestinationURL: resources.appendingPathComponent("en.lproj"))
        do { _ = try await engine.scan(app); fatalError("Absolute internal link accepted") } catch {}
        print("AppSlimmingSmoke: OK — real universal Mach-O thinned, chosen language omitted, ad hoc codesign verified, measured reduction \(result.savedBytes), original unchanged")
    }
}
