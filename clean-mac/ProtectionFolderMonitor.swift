import CoreServices
import Foundation

private final class ProtectionWatchCallback {
    let changed: @Sendable () -> Void
    init(changed: @escaping @Sendable () -> Void) { self.changed = changed }
}

/// FSEvents watches descendants as well as the selected directory. The stream
/// owns only its callback context; it does not retain the view model.
final class ProtectionFolderMonitor {
    private var stream: FSEventStreamRef?
    init(root: URL, changed: @escaping @Sendable () -> Void) throws {
        let home = try ScanScope.homeDirectory()
        guard root.path == root.standardizedFileURL.path, root.path == root.resolvingSymlinksInPath().path,
              !ScanScope.isFixture || root == home || root.path.hasPrefix(home.path + "/") else { throw ProtectionError.unsafePath }
        let callback = ProtectionWatchCallback(changed: changed)
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                return UnsafeRawPointer(Unmanaged<ProtectionWatchCallback>.fromOpaque(pointer).retain().toOpaque())
            }, release: { pointer in
                if let pointer { Unmanaged<ProtectionWatchCallback>.fromOpaque(pointer).release() }
            }, copyDescription: nil)
        guard let created = FSEventStreamCreate(nil, { _, context, count, _, _, _ in
            guard count > 0, let context else { return }
            Unmanaged<ProtectionWatchCallback>.fromOpaque(context).takeUnretainedValue().changed()
        }, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)) else {
            throw ProtectionError.inaccessible
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, DispatchQueue(label: "cleanmac.protection.folder", qos: .utility))
        guard FSEventStreamStart(created) else { stop(); throw ProtectionError.inaccessible }
    }
    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
    }
    deinit { stop() }
}
