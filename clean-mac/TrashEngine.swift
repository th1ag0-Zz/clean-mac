import Darwin
import Foundation

struct TrashIdentity: Sendable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
        mode = info.st_mode
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }

    func matches(_ info: stat) -> Bool {
        device == info.st_dev && inode == info.st_ino && mode == info.st_mode &&
        changedSeconds == info.st_ctimespec.tv_sec &&
        changedNanoseconds == info.st_ctimespec.tv_nsec
    }
}

struct TrashItem: Identifiable, Sendable {
    let name: String
    let url: URL
    let rootURL: URL
    let logicalBytes: UInt64
    let identity: TrashIdentity

    var id: String { url.path }
}

struct TrashSnapshot: Sendable {
    let home: URL
    let rootIdentity: TrashIdentity?
    let externalRoots: [URL: TrashIdentity]
    let items: [TrashItem]
    let issues: [String]

    init(home: URL, rootIdentity: TrashIdentity?, externalRoots: [URL: TrashIdentity] = [:],
         items: [TrashItem], issues: [String]) {
        self.home = home
        self.rootIdentity = rootIdentity
        self.externalRoots = externalRoots
        self.items = items
        self.issues = issues
    }

    var totalLogicalBytes: UInt64 {
        items.reduce(0) { partial, item in
            let sum = partial.addingReportingOverflow(item.logicalBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }
}

struct TrashOutcome: Identifiable, Sendable {
    let name: String
    let path: String
    let deleted: Bool
    let estimatedRemovedBytes: UInt64
    let error: String?

    var id: String { path }
}

struct TrashReport: Sendable {
    let outcomes: [TrashOutcome]
    var deletedCount: Int { outcomes.filter(\.deleted).count }
    var failedCount: Int { outcomes.count - deletedCount }
    var estimatedRemovedBytes: UInt64 {
        outcomes.reduce(0) { partial, outcome in
            let sum = partial.addingReportingOverflow(outcome.estimatedRemovedBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }
    // Clones APFS e outras mudanças no volume impedem uma medição confiável aqui.
    var freedBytes: UInt64? { nil }
}

actor TrashEngine {
    private let maximumDepth = 64

    func inspect() throws -> TrashSnapshot {
        let home = try ScanScope.homeDirectory()
        var items: [TrashItem] = []
        var issues: [String] = []
        let homeTrash = home.appendingPathComponent(".Trash", isDirectory: true)
        let homeIdentity = try inspectRoot(homeTrash, home: home, items: &items, issues: &issues)
        var externalRoots: [URL: TrashIdentity] = [:]
        for volume in try externalVolumes(home: home) {
            try Task.checkCancellation()
            let rootURL = externalTrashURL(volume: volume, home: home)
            if let identity = try inspectRoot(rootURL, home: home, items: &items, issues: &issues) {
                externalRoots[rootURL] = identity
            }
        }
        items.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        return TrashSnapshot(home: home, rootIdentity: homeIdentity,
                             externalRoots: externalRoots, items: items, issues: issues)
    }

    func empty(_ snapshot: TrashSnapshot) throws -> TrashReport {
        let home = try ScanScope.homeDirectory()
        guard home == snapshot.home else { throw TrashError.changed }
        var outcomes: [TrashOutcome] = []
        for item in snapshot.items {
            let expected = item.rootURL == home.appendingPathComponent(".Trash", isDirectory: true)
                ? snapshot.rootIdentity : snapshot.externalRoots[item.rootURL]
            guard let expected, let fd = openRoot(item.rootURL, home: home) else {
                outcomes.append(TrashOutcome(name: item.name, path: item.url.path, deleted: false,
                                             estimatedRemovedBytes: 0, error: "Lixeira indisponível."))
                continue
            }
            defer { close(fd) }
            var root = stat()
            guard fstat(fd, &root) == 0, expected.matches(root) else {
                outcomes.append(TrashOutcome(name: item.name, path: item.url.path, deleted: false,
                                             estimatedRemovedBytes: 0, error: "Lixeira alterada desde a revisão."))
                continue
            }
            var info = stat()
            guard item.name != ".", item.name != "..", !item.name.contains("/"),
                  item.name.withCString({ fstatat(fd, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0,
                  item.identity.matches(info) else {
                outcomes.append(TrashOutcome(name: item.name, path: item.url.path, deleted: false,
                                             estimatedRemovedBytes: 0,
                                             error: "Item alterado desde a revisão."))
                continue
            }
            var removedBytes: UInt64 = 0
            do {
                try remove(name: item.name, parentFD: fd, device: root.st_dev,
                           depth: 0, removedBytes: &removedBytes)
                outcomes.append(TrashOutcome(name: item.name, path: item.url.path, deleted: true,
                                             estimatedRemovedBytes: removedBytes, error: nil))
            } catch {
                outcomes.append(TrashOutcome(name: item.name, path: item.url.path, deleted: false,
                                             estimatedRemovedBytes: removedBytes,
                                             error: error.localizedDescription))
            }
        }
        return TrashReport(outcomes: outcomes)
    }

    private func externalBase(home: URL) -> URL {
        return ScanScope.isFixture ? home.appendingPathComponent("ExternalVolumes", isDirectory: true) : URL(fileURLWithPath: "/Volumes", isDirectory: true)
    }

    private func externalVolumes(home: URL) throws -> [String] {
        let fd = open(externalBase(home: home).path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return [] }
        guard fd >= 0 else { throw TrashError.inaccessible }
        defer { close(fd) }
        return try entries(in: fd).filter { name in
            let child = name.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            if child >= 0 { close(child); return true }
            return false
        }
    }

    private func externalTrashURL(volume: String, home: URL) -> URL {
        externalBase(home: home).appendingPathComponent(volume, isDirectory: true)
            .appendingPathComponent(".Trashes", isDirectory: true)
            .appendingPathComponent(String(getuid()), isDirectory: true)
    }

    private func openRoot(_ url: URL, home: URL) -> Int32? {
        let homeTrash = home.appendingPathComponent(".Trash", isDirectory: true)
        let base: URL
        let components: [String]
        if url == homeTrash {
            base = home
            components = [".Trash"]
        } else {
            base = externalBase(home: home)
            let prefix = base.path + "/"
            guard url.path.hasPrefix(prefix) else { return nil }
            components = String(url.path.dropFirst(prefix.count)).split(separator: "/").map(String.init)
            guard components.count == 3, components[1] == ".Trashes",
                  components[2] == String(getuid()) else { return nil }
        }
        var fd = open(base.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        for component in components {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            close(fd)
            guard next >= 0 else { return nil }
            fd = next
        }
        return fd
    }

    private func inspectRoot(_ url: URL, home: URL, items: inout [TrashItem],
                             issues: inout [String]) throws -> TrashIdentity? {
        guard let fd = openRoot(url, home: home) else {
            if FileManager.default.fileExists(atPath: url.path) { issues.append(url.path) }
            return nil
        }
        defer { close(fd) }
        var root = stat()
        guard fstat(fd, &root) == 0 else { throw TrashError.inaccessible }
        for name in try entries(in: fd) {
            try Task.checkCancellation()
            var info = stat()
            guard name.withCString({ fstatat(fd, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0,
                  info.st_dev == root.st_dev else { issues.append(url.appendingPathComponent(name).path); continue }
            do {
                let bytes = try measure(name: name, parentFD: fd, device: root.st_dev, depth: 0)
                var current = stat()
                guard name.withCString({ fstatat(fd, $0, &current, AT_SYMLINK_NOFOLLOW) }) == 0,
                      TrashIdentity(info).matches(current) else { throw TrashError.changed }
                items.append(TrashItem(name: name, url: url.appendingPathComponent(name),
                                       rootURL: url, logicalBytes: bytes, identity: TrashIdentity(info)))
            } catch { issues.append(url.appendingPathComponent(name).path) }
        }
        var current = stat()
        guard fstat(fd, &current) == 0, TrashIdentity(root).matches(current) else { throw TrashError.changed }
        return TrashIdentity(root)
    }

    private func entries(in directoryFD: Int32) throws -> [String] {
        let copiedFD = dup(directoryFD)
        guard copiedFD >= 0, let stream = fdopendir(copiedFD) else {
            if copiedFD >= 0 { close(copiedFD) }
            throw TrashError.inaccessible
        }
        defer { closedir(stream) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        guard errno == 0 else { throw TrashError.inaccessible }
        return names.sorted()
    }

    private func measure(
        name: String, parentFD: Int32, device: dev_t, depth: Int
    ) throws -> UInt64 {
        var info = stat()
        guard name.withCString({ fstatat(parentFD, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0,
              info.st_dev == device else { throw TrashError.changed }
        let kind = info.st_mode & S_IFMT
        if kind == S_IFREG { return UInt64(max(0, info.st_size)) }
        if kind == S_IFLNK { return 0 }
        if kind != S_IFDIR { throw TrashError.unsupportedItem }
        guard depth < maximumDepth else { throw TrashError.depthLimit }
        let fd = name.withCString { openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw TrashError.inaccessible }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == device,
              opened.st_ino == info.st_ino else { throw TrashError.changed }
        var total: UInt64 = 0
        for child in try entries(in: fd) {
            try Task.checkCancellation()
            let bytes = try measure(name: child, parentFD: fd, device: device, depth: depth + 1)
            let sum = total.addingReportingOverflow(bytes)
            total = sum.overflow ? UInt64.max : sum.partialValue
        }
        return total
    }

    private func remove(
        name: String, parentFD: Int32, device: dev_t, depth: Int,
        removedBytes: inout UInt64
    ) throws {
        var info = stat()
        guard name.withCString({ fstatat(parentFD, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0,
              info.st_dev == device else { throw TrashError.changed }
        let kind = info.st_mode & S_IFMT
        if kind == S_IFDIR {
            guard depth < maximumDepth else { throw TrashError.depthLimit }
            let fd = name.withCString { openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard fd >= 0 else { throw TrashError.inaccessible }
            defer { close(fd) }
            var opened = stat()
            guard fstat(fd, &opened) == 0, opened.st_dev == device,
                  opened.st_ino == info.st_ino else { throw TrashError.changed }
            for child in try entries(in: fd) {
                try remove(name: child, parentFD: fd, device: device,
                           depth: depth + 1, removedBytes: &removedBytes)
            }
            guard name.withCString({ unlinkat(parentFD, $0, AT_REMOVEDIR) }) == 0 else {
                throw TrashError.inaccessible
            }
        } else if kind == S_IFREG || kind == S_IFLNK {
            guard name.withCString({ unlinkat(parentFD, $0, 0) }) == 0 else {
                throw TrashError.inaccessible
            }
            if kind == S_IFREG, info.st_blocks > 0 {
                let blocks = UInt64(info.st_blocks).multipliedReportingOverflow(by: 512)
                let sum = removedBytes.addingReportingOverflow(blocks.overflow ? UInt64.max : blocks.partialValue)
                removedBytes = sum.overflow ? UInt64.max : sum.partialValue
            }
        } else {
            throw TrashError.unsupportedItem
        }
    }
}

enum TrashError: LocalizedError {
    case inaccessible
    case changed
    case depthLimit
    case unsupportedItem

    var errorDescription: String? {
        switch self {
        case .inaccessible: "Não foi possível acessar um item da Lixeira."
        case .changed: "A Lixeira mudou desde a revisão; analise novamente."
        case .depthLimit: "Pasta profunda demais para esvaziar com segurança."
        case .unsupportedItem: "Tipo de item não suportado na Lixeira."
        }
    }
}
