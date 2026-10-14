import Foundation
import Darwin
import SQLite3

enum SnapshotName {
    static func date(from name: String) -> String? {
        let prefix = "com.apple.TimeMachine."
        guard name.hasPrefix(prefix), name.hasSuffix(".local") else { return nil }
        let date = String(name.dropFirst(prefix.count).dropLast(6))
        let bytes = Array(date.utf8)
        guard bytes.count == 17, bytes[4] == 45, bytes[7] == 45, bytes[10] == 45,
              bytes.enumerated().allSatisfy({ [4, 7, 10].contains($0.offset) || (48...57).contains($0.element) }) else { return nil }
        return date
    }
}

struct MountedImage: Identifiable, Sendable {
    var id: String { device }
    let device: String
    let path: String
    static func parse(_ plist: String) -> [MountedImage] {
        guard let data = plist.data(using: .utf8),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = values["system-entities"] as? [[String: Any]] else { return [] }
        return entities.compactMap {
            guard let device = $0["dev-entry"] as? String, device.hasPrefix("/dev/disk"),
                  let path = $0["mount-point"] as? String, path.hasPrefix("/Volumes/") else { return nil }
            return MountedImage(device: device, path: path)
        }
    }
}

enum PermanentDeletion {
    struct Item: Identifiable, Sendable {
        var id: String { url.path }
        let url: URL
        let bytes: UInt64
        let inode: UInt64
        let device: UInt64
        let modificationDate: Date?
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let parentInode: UInt64
        let parentDevice: UInt64
    }
    struct Outcome: Sendable { var deletedIDs: Set<String> = []; var errors: [String] = [] }
    enum DeletionError: LocalizedError {
        case notRegularFile, changed, outsideFixture
        var errorDescription: String? {
            switch self {
            case .notRegularFile: "Escolha um arquivo comum. Pastas, pacotes e links não são aceitos."
            case .changed: "O arquivo ou sua pasta mudou depois da seleção. Selecione-o novamente."
            case .outsideFixture: "Na sessão de testes, somente arquivos dentro da pasta de teste são aceitos."
            }
        }
    }

    static func inspect(_ url: URL) throws -> Item {
        let parent = try openParent(of: url)
        defer { close(parent.fd) }
        let metadata = try fileMetadata(parent.fd, parent.name)
        var directory = stat()
        guard fstat(parent.fd, &directory) == 0 else { throw posixError() }
        return Item(url: parent.url, bytes: UInt64(metadata.st_size), inode: UInt64(metadata.st_ino),
                    device: UInt64(metadata.st_dev),
                    modificationDate: Date(timeIntervalSince1970: Double(metadata.st_mtimespec.tv_sec) + Double(metadata.st_mtimespec.tv_nsec) / 1_000_000_000),
                    modificationSeconds: Int64(metadata.st_mtimespec.tv_sec), modificationNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
                    parentInode: UInt64(directory.st_ino), parentDevice: UInt64(directory.st_dev))
    }

    static func remove(_ items: [Item]) -> Outcome {
        var outcome = Outcome()
        for item in items {
            do {
                let parent = try openParent(of: item.url)
                defer { close(parent.fd) }
                var directory = stat()
                guard fstat(parent.fd, &directory) == 0 else { throw posixError() }
                let current = try fileMetadata(parent.fd, parent.name)
                guard item.parentInode == UInt64(directory.st_ino), item.parentDevice == UInt64(directory.st_dev),
                      item.inode == UInt64(current.st_ino), item.device == UInt64(current.st_dev),
                      item.bytes == UInt64(current.st_size),
                      item.modificationSeconds == Int64(current.st_mtimespec.tv_sec),
                      item.modificationNanoseconds == Int64(current.st_mtimespec.tv_nsec) else { throw DeletionError.changed }
                // The directory descriptor anchors the operation even if an ancestor is renamed.
                // unlinkat doesn't recurse into directories or follow a final symlink.
                guard unlinkat(parent.fd, parent.name, 0) == 0 else { throw posixError() }
                outcome.deletedIDs.insert(item.id)
            } catch { outcome.errors.append("\(item.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return outcome
    }

    private static func fileMetadata(_ parent: Int32, _ name: String) throws -> stat {
        var metadata = stat()
        guard fstatat(parent, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_size >= 0 else { throw DeletionError.notRegularFile }
        return metadata
    }

    private static func openParent(of url: URL) throws -> (fd: Int32, name: String, url: URL) {
        let canonical = try canonicalURL(url)
        if let fixture = ProcessInfo.processInfo.environment["CLEANUP_MAC_FIXTURE_HOME"] {
            let root = try canonicalURL(URL(fileURLWithPath: fixture)).path
            guard canonical.path.hasPrefix(root + "/") else { throw DeletionError.outsideFixture }
        }
        let components = canonical.path.split(separator: "/").map(String.init)
        guard let name = components.last else { throw DeletionError.notRegularFile }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        do {
            for component in components.dropLast() {
                let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard next >= 0 else { throw posixError() }
                close(descriptor)
                descriptor = next
            }
            return (descriptor, name, canonical)
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func canonicalURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0") else { throw DeletionError.notRegularFile }
        let components = url.path.split(separator: "/").map(String.init)
        guard !components.contains(".."), !components.contains(".") else { throw DeletionError.notRegularFile }
        var path = "/" + components.joined(separator: "/")
        // These immutable macOS root aliases have known canonical destinations.
        // Every other ancestor must be a real directory, enforced by openat below.
        for alias in ["/tmp", "/var", "/etc"] {
            if path == alias || path.hasPrefix(alias + "/") { path = "/private" + path; break }
        }
        return URL(fileURLWithPath: path)
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

/// Compacts only the index database; SQLite's backup API includes committed WAL data.
enum MailIndexOptimizer {
    static func optimize() -> String {
        guard !LocalCommand.isFixture else { return "Operação desativada na sessão de testes." }
        let mail = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mail", isDirectory: true)
        do {
            let versions = try FileManager.default.contentsOfDirectory(at: mail, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("V") && Int($0.lastPathComponent.dropFirst()) != nil }
                .sorted { Int($0.lastPathComponent.dropFirst())! > Int($1.lastPathComponent.dropFirst())! }
            guard let version = versions.first else { return "Nenhum índice local do Mail encontrado." }
            let index = version.appendingPathComponent("MailData/Envelope Index")
            _ = try PermanentDeletion.inspect(index)
            // Mail may have been opened after the confirmation.
            let mailRunning = LocalCommand.run("/usr/bin/pgrep", ["-x", "Mail"])
            guard mailRunning.status == 1 else { return "O Mail está aberto ou não foi possível verificar seu estado. Feche-o e tente novamente." }
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let backup = support.appendingPathComponent("CleanMac/MailIndexBackups/\(UUID().uuidString)/Envelope Index")
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            let sizes = try optimizeDatabase(at: index, backupURL: backup)
            return "Índice do Mail otimizado: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: sizes.before), countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: Int64(clamping: sizes.after), countStyle: .file)).\nBackup consistente: \(backup.path)"
        } catch { return "Não foi possível otimizar o índice do Mail: \(error.localizedDescription)" }
    }

    static func optimizeDatabase(at index: URL, backupURL: URL) throws -> (before: UInt64, after: UInt64) {
        let before = try PermanentDeletion.inspect(index).bytes
        var database: OpaquePointer?
        var backupDatabase: OpaquePointer?
        let openStatus = sqlite3_open_v2(index.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil)
        defer { if let database { sqlite3_close(database) } }
        guard openStatus == SQLITE_OK, let database else { throw databaseError(database, operation: "Abrir índice") }
        sqlite3_busy_timeout(database, 5000)
        // Refuse replacing any pre-existing backup path.
        guard !FileManager.default.fileExists(atPath: backupURL.path) else {
            throw NSError(domain: "MailIndex", code: 1, userInfo: [NSLocalizedDescriptionKey: "O destino do backup já existe."])
        }
        let backupOpenStatus = sqlite3_open_v2(backupURL.path, &backupDatabase, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        defer { if let backupDatabase { sqlite3_close(backupDatabase) } }
        guard backupOpenStatus == SQLITE_OK, let backupDatabase else { throw databaseError(backupDatabase, operation: "Criar backup") }
        guard let backup = sqlite3_backup_init(backupDatabase, "main", database, "main") else { throw databaseError(backupDatabase, operation: "Preparar backup") }
        let copyStatus = sqlite3_backup_step(backup, -1)
        let finishStatus = sqlite3_backup_finish(backup)
        guard copyStatus == SQLITE_DONE, finishStatus == SQLITE_OK else { throw databaseError(backupDatabase, operation: "Salvar backup consistente") }
        guard sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE); VACUUM; PRAGMA optimize;", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "MailIndex", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(databaseError(database, operation: "Compactar índice").localizedDescription). Backup preservado em \(backupURL.path)"])
        }
        return (before, try PermanentDeletion.inspect(index).bytes)
    }

    private static func databaseError(_ database: OpaquePointer?, operation: String) -> NSError {
        let detail = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite indisponível"
        return NSError(domain: "MailIndex", code: Int(database.map { sqlite3_errcode($0) } ?? SQLITE_ERROR),
                       userInfo: [NSLocalizedDescriptionKey: "\(operation): \(detail)"])
    }
}
