import CryptoKit
import Darwin
import Foundation

struct PersonalFileIdentity: Sendable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ info: stat) {
        device = info.st_dev; inode = info.st_ino; size = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }

    func matches(_ info: stat) -> Bool {
        device == info.st_dev && inode == info.st_ino && size == info.st_size &&
        modifiedSeconds == info.st_mtimespec.tv_sec && modifiedNanoseconds == info.st_mtimespec.tv_nsec &&
        changedSeconds == info.st_ctimespec.tv_sec && changedNanoseconds == info.st_ctimespec.tv_nsec
    }
}

struct PersonalFileSelection: Identifiable, Sendable {
    let url: URL
    let logicalBytes: UInt64
    let identity: PersonalFileIdentity
    var id: String { url.path }
}

struct PersonalDuplicateConstraint: Sendable {
    let digest: String
    let files: [PersonalFileSelection]
}

struct PersonalFileRemovalReport: Sendable {
    let moved: [URL]
    let failures: [String]
    var message: String {
        let result = "\(moved.count) arquivo(s) movido(s) para a Lixeira. O espaço será liberado ao esvaziá-la."
        return failures.isEmpty ? result : result + " " + failures.joined(separator: " · ")
    }
}

enum PersonalFileError: LocalizedError {
    case unsafeLocation, changed, preserveDuplicate
    var errorDescription: String? {
        switch self {
        case .unsafeLocation: "Local não permitido: links, pacotes, arquivos de nuvem e pastas do sistema ficam fora desta operação."
        case .changed: "Um arquivo mudou desde a análise. Analise novamente antes de movê-lo."
        case .preserveDuplicate: "Mantenha pelo menos uma cópia idêntica de cada grupo de duplicados."
        }
    }
}

/// Shared validation for personal-file scans and their reversible Trash actions.
enum PersonalFileActions {
    static let personalFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
    private static let cloudNames = ["dropbox", "onedrive", "google drive", "googledrive", "icloud drive", "icloud~", "cloudstorage", "mobile documents", "pcloud", "box sync", "box drive"]
    private static let packageExtensions: Set<String> = ["app", "bundle", "framework", "photoslibrary", "photolibrary", "musiclibrary", "band", "logicx", "pages", "numbers", "key", "rtfd", "pkg", "xcodeproj", "xcworkspace"]

    /// Checks every ancestor with lstat: resolving a symlink does not make it safe.
    static func validateLocation(_ url: URL, home: URL, allowExternalFolder: Bool = false) throws {
        let normalized = url.standardizedFileURL
        guard normalized.path == url.path, normalized.path != "/",
              normalized.resolvingSymlinksInPath().path == normalized.path else { throw PersonalFileError.unsafeLocation }
        let volume = try normalized.resourceValues(forKeys: [.volumeIsLocalKey])
        guard volume.volumeIsLocal == true else { throw PersonalFileError.unsafeLocation }
        let homePath = home.standardizedFileURL.path
        let relative = normalized.path.hasPrefix(homePath + "/") ? String(normalized.path.dropFirst(homePath.count + 1)) : nil
        if !allowExternalFolder {
            guard let relative, let first = relative.split(separator: "/").first,
                  personalFolders.contains(String(first)) else { throw PersonalFileError.unsafeLocation }
        } else {
            let forbidden = ["/System", "/Library", "/Applications", "/bin", "/sbin", "/usr", "/dev", "/etc", "/private/var", "/private/etc"]
            guard !forbidden.contains(where: { normalized.path == $0 || normalized.path.hasPrefix($0 + "/") }),
                  normalized.path != homePath,
                  normalized.path != homePath + "/Library",
                  !normalized.path.hasPrefix(homePath + "/Library/") else { throw PersonalFileError.unsafeLocation }
            if ScanScope.isFixture {
                guard normalized.path.hasPrefix(homePath + "/") else { throw PersonalFileError.unsafeLocation }
            }
        }
        var ancestor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in normalized.pathComponents.dropFirst() {
            ancestor.appendPathComponent(component)
            var info = stat()
            guard lstat(ancestor.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { throw PersonalFileError.unsafeLocation }
            let name = component.lowercased()
            guard name != "box", !cloudNames.contains(where: { name.contains($0) }),
                  !packageExtensions.contains(ancestor.pathExtension.lowercased()) else { throw PersonalFileError.unsafeLocation }
            let values = try ancestor.resourceValues(forKeys: [.isPackageKey, .isUbiquitousItemKey])
            guard values.isPackage != true, values.isUbiquitousItem != true else { throw PersonalFileError.unsafeLocation }
        }
    }

    static func validate(_ file: PersonalFileSelection, home: URL, allowExternalFolder: Bool = false) throws {
        try validateLocation(file.url, home: home, allowExternalFolder: allowExternalFolder)
        var info = stat()
        guard lstat(file.url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size >= 0, file.identity.matches(info),
              UInt64(info.st_size) == file.logicalBytes else { throw PersonalFileError.changed }
    }

    static func digest(_ file: PersonalFileSelection, home: URL) throws -> String {
        try validate(file, home: home)
        let descriptor = open(file.url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PersonalFileError.changed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, file.identity.matches(opened) else { throw PersonalFileError.changed }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if chunk.isEmpty { break }
            hash.update(data: chunk)
        }
        try validate(file, home: home)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func moveToTrash(_ files: [PersonalFileSelection], duplicates: [PersonalDuplicateConstraint] = [],
                            allowExternalFolder: Bool = false) throws -> PersonalFileRemovalReport {
        let home = try ScanScope.homeDirectory()
        let selected = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.id < $1.id }
        let selectedIDs = Set(selected.map(\.id))
        // Preflight the entire selection before any move, including preserved copies.
        for file in selected { try validate(file, home: home, allowExternalFolder: allowExternalFolder) }
        for group in duplicates where group.files.contains(where: { selectedIDs.contains($0.id) }) {
            let survivors = group.files.filter { !selectedIDs.contains($0.id) }
            var verifiedSurvivor = false
            for survivor in survivors {
                if (try? digest(survivor, home: home)) == group.digest { verifiedSurvivor = true; break }
            }
            guard verifiedSurvivor else { throw PersonalFileError.preserveDuplicate }
        }
        var moved: [URL] = []
        var failures: [String] = []
        for file in selected {
            do {
                try validate(file, home: home, allowExternalFolder: allowExternalFolder)
                if ScanScope.isFixture {
                    // Test operations write only to the validated fixture's private Trash.
                    let trash = home.appendingPathComponent(".Trash", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: trash.path) {
                        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
                    }
                    var info = stat()
                    guard lstat(trash.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                          trash.resolvingSymlinksInPath().path == trash.path else { throw PersonalFileError.unsafeLocation }
                    try FileManager.default.moveItem(at: file.url, to: trash.appendingPathComponent(UUID().uuidString + "-" + file.url.lastPathComponent))
                } else {
                    var destination: NSURL?
                    try FileManager.default.trashItem(at: file.url, resultingItemURL: &destination)
                    guard destination != nil else { throw PersonalFileError.changed }
                }
                moved.append(file.url)
            } catch {
                failures.append("\(file.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return PersonalFileRemovalReport(moved: moved, failures: failures)
    }
}
