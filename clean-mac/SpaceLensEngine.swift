import Darwin
import Foundation
import CoreGraphics

enum SpaceLensError: LocalizedError {
    case cannotOpenHome
    case invalidSelection
    case changed
    var errorDescription: String? {
        switch self {
        case .cannotOpenHome: "Não foi possível acessar a pasta pessoal."
        case .invalidSelection: "Este arquivo não pode ser removido por esta tela."
        case .changed: "O arquivo mudou desde a análise. Analise novamente antes de removê-lo."
        }
    }
}

typealias SpaceLensIdentity = PersonalFileIdentity

struct SpaceLensItem: Identifiable, Sendable {
    let url: URL
    let name: String
    let logicalBytes: UInt64
    let fileCount: Int
    let isDirectory: Bool
    let identity: SpaceLensIdentity?
    let children: [SpaceLensItem]

    var id: String { url.path }
}

struct SpaceLensSnapshot: Sendable {
    let roots: [SpaceLensItem]
    let scannedFiles: Int
    let inaccessibleLocations: Int
    let truncated: Bool
}

actor SpaceLensEngine {
    private static let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
    private static let maximumEntries = 200_000

    private final class Node {
        let url: URL
        let name: String
        let isDirectory: Bool
        let identity: SpaceLensIdentity?
        var bytes: UInt64 = 0
        var files = 0
        var children: [String: Node] = [:]

        init(url: URL, name: String, isDirectory: Bool, identity: SpaceLensIdentity? = nil) {
            self.url = url
            self.name = name
            self.isDirectory = isDirectory
            self.identity = identity
        }

        func snapshot() -> SpaceLensItem {
            var ordered: [SpaceLensItem] = children.values.map { child in child.snapshot() }
            ordered.sort { lhs, rhs in
                if lhs.logicalBytes == rhs.logicalBytes { return lhs.name < rhs.name }
                return lhs.logicalBytes > rhs.logicalBytes
            }
            return SpaceLensItem(url: url, name: name, logicalBytes: bytes,
                                 fileCount: files, isDirectory: isDirectory,
                                 identity: identity, children: ordered)
        }
    }

    func scan(root selectedRoot: URL? = nil) throws -> SpaceLensSnapshot {
        let home = try ScanScope.homeDirectory()
        var homeInfo = stat()
        guard lstat(home.path, &homeInfo) == 0, homeInfo.st_mode & S_IFMT == S_IFDIR else {
            throw SpaceLensError.cannotOpenHome
        }

        if let selectedRoot { try PersonalFileActions.validateLocation(selectedRoot, home: home, allowExternalFolder: true) }
        var roots: [SpaceLensItem] = []
        var scannedFiles = 0
        var inaccessible = 0
        var truncated = false
        var visitedEntries = 0
        let manager = FileManager.default

        let rootURLs = selectedRoot.map { [$0] } ?? Self.roots.map { home.appendingPathComponent($0, isDirectory: true) }
        for rootURL in rootURLs {
            let name = rootURL.lastPathComponent
            try Task.checkCancellation()
            var rootInfo = stat()
            guard lstat(rootURL.path, &rootInfo) == 0 else {
                if errno != ENOENT { inaccessible += 1 }
                continue
            }
            guard rootInfo.st_mode & S_IFMT == S_IFDIR else { continue }
            guard (try? PersonalFileActions.validateLocation(rootURL, home: home, allowExternalFolder: selectedRoot != nil)) != nil else { continue }
            let root = Node(url: rootURL, name: name, isDirectory: true)
            guard let entries = manager.enumerator(at: rootURL, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                   errorHandler: { _, _ in
                                                       inaccessible += 1
                                                       return true
                                                   }) else {
                inaccessible += 1
                continue
            }
            for case let url as URL in entries {
                try Task.checkCancellation()
                visitedEntries += 1
                if visitedEntries > Self.maximumEntries { truncated = true; break }
                guard (try? PersonalFileActions.validateLocation(url, home: home, allowExternalFolder: selectedRoot != nil)) != nil else { entries.skipDescendants(); continue }
                var info = stat()
                guard lstat(url.path, &info) == 0 else { inaccessible += 1; continue }
                guard info.st_dev == rootInfo.st_dev else { entries.skipDescendants(); continue }
                let type = info.st_mode & S_IFMT
                guard type == S_IFDIR || type == S_IFREG else { entries.skipDescendants(); continue }

                let relative = String(url.path.dropFirst(rootURL.path.count + 1))
                let parts = relative.split(separator: "/").map(String.init)
                guard !parts.isEmpty else { continue }
                var node = root
                for (index, part) in parts.enumerated() {
                    let isLast = index == parts.count - 1
                    if let child = node.children[part] {
                        node = child
                    } else {
                        let childURL = node.url.appendingPathComponent(part, isDirectory: !isLast || type == S_IFDIR)
                        let child = Node(url: childURL, name: part, isDirectory: !isLast || type == S_IFDIR,
                                         identity: isLast && type == S_IFREG ? SpaceLensIdentity(info) : nil)
                        node.children[part] = child
                        node = child
                    }
                }
                guard type == S_IFREG, info.st_size >= 0 else { continue }
                scannedFiles += 1
                let bytes = UInt64(info.st_size)
                node.bytes = bytes
                node.files = 1
                var ancestor = root
                ancestor.bytes = Self.saturatingAdd(ancestor.bytes, bytes)
                ancestor.files += 1
                for part in parts.dropLast() {
                    guard let child = ancestor.children[part] else { break }
                    child.bytes = Self.saturatingAdd(child.bytes, bytes)
                    child.files += 1
                    ancestor = child
                }
            }
            roots.append(root.snapshot())
            if truncated { break }
        }
        roots.sort { $0.logicalBytes > $1.logicalBytes }
        return SpaceLensSnapshot(roots: roots, scannedFiles: scannedFiles,
                                 inaccessibleLocations: inaccessible, truncated: truncated)
    }

    func moveToTrash(_ item: SpaceLensItem) throws {
        guard !item.isDirectory, let identity = item.identity else { throw SpaceLensError.invalidSelection }
        let result = try PersonalFileActions.moveToTrash([
            PersonalFileSelection(url: item.url, logicalBytes: item.logicalBytes, identity: identity)
        ], allowExternalFolder: true)
        if !result.failures.isEmpty { throw SpaceLensError.changed }
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }
}

/// Balanced binary partition. Each rectangle receives exactly its share of total area.
enum SpaceTreemapLayout {
    static func frames(weights: [Double], in bounds: CGRect) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        var frames = [CGRect](repeating: .zero, count: weights.count)
        func partition(_ range: Range<Int>, _ rect: CGRect) {
            guard range.count > 1 else { if let index = range.first { frames[index] = rect }; return }
            let total = range.reduce(0.0) { $0 + weights[$1] }
            guard total > 0 else { return }
            var sum = 0.0
            var split = range.lowerBound + 1
            for index in range.dropLast() {
                sum += weights[index]
                split = index + 1
                if sum >= total / 2 { break }
            }
            let ratio = CGFloat(sum / total)
            if rect.width >= rect.height {
                let width = rect.width * ratio
                partition(range.lowerBound..<split, CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
                partition(split..<range.upperBound, CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height))
            } else {
                let height = rect.height * ratio
                partition(range.lowerBound..<split, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height))
                partition(split..<range.upperBound, CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height))
            }
        }
        partition(weights.indices, bounds)
        return frames
    }
}

