import CryptoKit
import Darwin
import Foundation

@main
struct PersonalFileActionsSmoke {
    static func main() async throws {
        guard ScanScope.isFixture else { fatalError("Fixture required") }
        let home = try ScanScope.homeDirectory()
        let root = home.appendingPathComponent("Documents/personal-actions-\(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let payload = Data(repeating: 42, count: 2048)
        func create(_ name: String, payload data: Data = payload) throws -> PersonalFileSelection {
            let url = root.appendingPathComponent(name)
            try data.write(to: url)
            var info = stat(); precondition(lstat(url.path, &info) == 0)
            return PersonalFileSelection(url: url, logicalBytes: UInt64(info.st_size), identity: PersonalFileIdentity(info))
        }
        func rejected(_ action: () throws -> Void) {
            do { try action(); fatalError("Unsafe action accepted") } catch {}
        }
        let first = try create("original.bin")
        let copyName = "copy-\(UUID().uuidString).bin"
        let second = try create(copyName)
        let digest = try PersonalFileActions.digest(first, home: home)
        let group = PersonalDuplicateConstraint(digest: digest, files: [first, second])
        rejected { _ = try PersonalFileActions.moveToTrash([first, second], duplicates: [group]) }
        precondition(manager.fileExists(atPath: first.url.path) && manager.fileExists(atPath: second.url.path))
        let staleOriginal = try create("stale-original.bin")
        let staleCopy = try create("stale-copy.bin")
        let staleGroup = PersonalDuplicateConstraint(digest: digest, files: [staleOriginal, staleCopy])
        try Data(repeating: 7, count: payload.count).write(to: staleOriginal.url)
        rejected { _ = try PersonalFileActions.moveToTrash([staleCopy], duplicates: [staleGroup]) }
        precondition(manager.fileExists(atPath: staleCopy.url.path))
        let changed = try create("changed.bin")
        try Data([1, 2, 3]).write(to: changed.url)
        rejected { _ = try PersonalFileActions.moveToTrash([changed]) }
        let swapped = try create("swapped.bin")
        try manager.removeItem(at: swapped.url)
        try manager.createSymbolicLink(at: swapped.url, withDestinationURL: first.url)
        rejected { _ = try PersonalFileActions.moveToTrash([swapped]) }
        let subfolder = root.appendingPathComponent("sub", isDirectory: true)
        try manager.createDirectory(at: subfolder, withIntermediateDirectories: false)
        let nestedURL = subfolder.appendingPathComponent("nested.bin")
        try payload.write(to: nestedURL)
        var nestedInfo = stat(); precondition(lstat(nestedURL.path, &nestedInfo) == 0)
        let nested = PersonalFileSelection(url: nestedURL, logicalBytes: UInt64(nestedInfo.st_size), identity: PersonalFileIdentity(nestedInfo))
        try manager.moveItem(at: subfolder, to: root.appendingPathComponent("real-sub"))
        try manager.createSymbolicLink(at: subfolder, withDestinationURL: root.appendingPathComponent("real-sub"))
        rejected { _ = try PersonalFileActions.moveToTrash([nested]) }
        for name in ["Dropbox", "Sample.app", "Photos.photoslibrary"] {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: false)
            try payload.write(to: folder.appendingPathComponent("data.bin"))
            rejected { try PersonalFileActions.validateLocation(folder.appendingPathComponent("data.bin"), home: home) }
        }
        rejected { try PersonalFileActions.validateLocation(home, home: home, allowExternalFolder: true) }
        let report = try PersonalFileActions.moveToTrash([second], duplicates: [group])
        precondition(report.moved == [second.url] && report.failures.isEmpty)
        precondition(manager.fileExists(atPath: first.url.path) && !manager.fileExists(atPath: second.url.path))
        // Clean up exactly this test's moved item, never the fixture Trash itself.
        let trash = home.appendingPathComponent(".Trash")
        for url in try manager.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) where url.lastPathComponent.hasSuffix("-" + copyName) {
            if (try? Data(contentsOf: url)) == payload { try manager.removeItem(at: url) }
        }
        print("PersonalFileActionsSmoke: OK — preserve duplicate, mutation, file/ancestor symlink, cloud, package, home and fixture Trash")
    }
}
