import Darwin
import Foundation

struct LargeFile: Identifiable, Sendable {
    let url: URL
    let relativePath: String
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
    let identity: PersonalFileIdentity
    let modifiedAt: Date

    var id: String { relativePath }
    var selection: PersonalFileSelection { PersonalFileSelection(url: url, logicalBytes: logicalBytes, identity: identity) }
}

struct LargeFilesSnapshot: Sendable {
    let files: [LargeFile]
    let scannedFiles: Int
    let inaccessibleLocations: Int
}

actor LargeFilesEngine {
    static let minimumBytes: UInt64 = 100 * 1_024 * 1_024
    private static let folders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]

    func scan() throws -> LargeFilesSnapshot {
        let home = try ScanScope.homeDirectory()
        var homeInfo = stat()
        guard lstat(home.path, &homeInfo) == 0, homeInfo.st_mode & S_IFMT == S_IFDIR else {
            throw ScanError.cannotOpenHome
        }

        var files: [LargeFile] = []
        var scannedFiles = 0
        var inaccessibleLocations = 0
        let manager = FileManager.default

        for folderName in Self.folders {
            try Task.checkCancellation()
            let folder = home.appendingPathComponent(folderName, isDirectory: true)
            var folderInfo = stat()
            guard lstat(folder.path, &folderInfo) == 0 else {
                if errno != ENOENT { inaccessibleLocations += 1 }
                continue
            }
            guard folderInfo.st_mode & S_IFMT == S_IFDIR,
                  folderInfo.st_dev == homeInfo.st_dev else { continue }
            guard (try? PersonalFileActions.validateLocation(folder, home: home)) != nil else { continue }

            guard let entries = manager.enumerator(at: folder,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                    errorHandler: { _, _ in
                                                        inaccessibleLocations += 1
                                                        return true
                                                    }) else {
                inaccessibleLocations += 1
                continue
            }
            for case let url as URL in entries {
                try Task.checkCancellation()
                var info = stat()
                guard (try? PersonalFileActions.validateLocation(url, home: home)) != nil else {
                    entries.skipDescendants()
                    continue
                }
                guard lstat(url.path, &info) == 0 else {
                    inaccessibleLocations += 1
                    continue
                }
                guard info.st_dev == homeInfo.st_dev else {
                    entries.skipDescendants()
                    continue
                }
                guard info.st_mode & S_IFMT == S_IFREG else {
                    if info.st_mode & S_IFMT != S_IFDIR { entries.skipDescendants() }
                    continue
                }
                scannedFiles += 1
                guard info.st_size >= 0, UInt64(info.st_size) >= Self.minimumBytes else { continue }
                let relativePath = String(url.path.dropFirst(home.path.count + 1))
                files.append(LargeFile(url: url, relativePath: relativePath,
                                       logicalBytes: UInt64(info.st_size),
                                       allocatedBytes: info.st_blocks >= 0 ? UInt64(info.st_blocks) * 512 : 0,
                                       identity: PersonalFileIdentity(info),
                                       modifiedAt: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))))
            }
        }
        files.sort {
            $0.logicalBytes == $1.logicalBytes
                ? $0.relativePath < $1.relativePath
                : $0.logicalBytes > $1.logicalBytes
        }
        return LargeFilesSnapshot(files: files, scannedFiles: scannedFiles,
                                  inaccessibleLocations: inaccessibleLocations)
    }

    func moveToTrash(_ files: [LargeFile]) throws -> PersonalFileRemovalReport {
        try PersonalFileActions.moveToTrash(files.map(\.selection))
    }
}
