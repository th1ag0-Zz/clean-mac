import Darwin
import Foundation

enum AdvancedCategory: String, CaseIterable, Sendable {
    case systemCaches, systemLogs, xcode, mailDownloads, deviceBackups, documentVersions, aiModels, aiCaches, brokenPreferences, deletedUsers

    var title: String {
        switch self {
        case .systemCaches: "Cache e temporários do sistema"
        case .systemLogs: "Logs do sistema"
        case .xcode: "Arquivos gerados pelo Xcode"
        case .mailDownloads: "Downloads de anexos do Mail"
        case .deviceBackups: "Backups de iPhone e iPad"
        case .documentVersions: "Versões anteriores de documentos"
        case .aiModels: "Modelos locais de IA"
        case .aiCaches: "Caches e registros de IA"
        case .brokenPreferences: "Preferências ilegíveis"
        case .deletedUsers: "Arquivos de usuários apagados"
        }
    }
}

private enum AdvancedOrigin: Sendable { case home, system }
private enum AdvancedKind: Sendable { case file, directory, versions }

private struct AdvancedRule: Sendable {
    let category: AdvancedCategory
    let origin: AdvancedOrigin
    let path: [String]
    let kind: AdvancedKind
    let age: TimeInterval
    let extensions: Set<String>?
    let recursive: Bool
    let reason: String

    init(_ category: AdvancedCategory, _ origin: AdvancedOrigin, _ path: [String],
         _ kind: AdvancedKind, days: Double = 30, extensions: Set<String>? = nil,
         recursive: Bool = true, reason: String) {
        self.category = category
        self.origin = origin
        self.path = path
        self.kind = kind
        self.age = days * 86_400
        self.extensions = extensions
        self.recursive = recursive
        self.reason = reason
    }
}

private enum AdvancedCatalog {
    static let rules: [AdvancedRule] = [
        AdvancedRule(.deletedUsers, .system, ["Users", "Deleted Users"], .file, days: 0,
                     extensions: ["dmg", "zip"], recursive: false,
                     reason: "Arquivo de uma conta de usuário apagada. Confirme que nenhum dado precisa ser recuperado."),
        AdvancedRule(.aiModels, .home, [".ollama", "models"], .directory, days: 0,
                     reason: "Modelo local do Ollama. Remover exige baixar ou reconstruir o modelo antes do próximo uso."),
        AdvancedRule(.aiModels, .home, [".lmstudio", "models"], .directory, days: 0,
                     reason: "Modelo local do LM Studio. Confira os projetos que dependem dele antes de remover."),
        AdvancedRule(.aiModels, .home, [".cache", "huggingface", "hub"], .directory, days: 0,
                     reason: "Modelo no cache local Hugging Face. Remover pode exigir baixar o modelo novamente."),
        AdvancedRule(.aiCaches, .home, [".ollama", "logs"], .file,
                     reason: "Registro local do Ollama sem alterações há 30 dias."),
        AdvancedRule(.aiCaches, .home, ["Library", "Logs", "Claude"], .file,
                     reason: "Registro local de ferramenta de IA sem alterações há 30 dias."),
        AdvancedRule(.aiCaches, .home, ["Library", "Caches", "com.anthropic.claudefordesktop"], .file,
                     reason: "Cache de ferramenta de IA sem alterações há 30 dias."),
        AdvancedRule(.brokenPreferences, .home, ["Library", "Preferences"], .file, days: 30,
                     extensions: ["plist"], recursive: false,
                     reason: "Preferência que não pôde ser interpretada como plist, sem alterações há 30 dias. Confira o app responsável antes de remover."),
        AdvancedRule(.xcode, .home, ["Library", "Developer", "Xcode", "Archives"], .directory,
                     reason: "Arquivo de distribuição do Xcode sem alterações há 30 dias. Pode ser necessário para simbolicar falhas ou redistribuir builds."),
        AdvancedRule(.xcode, .home, ["Library", "Developer", "Xcode", "iOS DeviceSupport"], .directory,
                     reason: "Suporte local de dispositivo do Xcode sem alterações há 30 dias; pode ser recriado."),

        AdvancedRule(.systemCaches, .system, ["Library", "Caches"], .file,
                     reason: "Cache da Biblioteca do sistema sem alterações há 30 dias."),
        AdvancedRule(.systemCaches, .system, ["private", "var", "tmp"], .file,
                     reason: "Arquivo temporário sem alterações há 30 dias."),
        AdvancedRule(.systemLogs, .system, ["Library", "Logs"], .file,
                     extensions: ["log", "ips", "crash", "diag"],
                     reason: "Log ou relatório do sistema sem alterações há 30 dias."),
        AdvancedRule(.systemLogs, .system, ["private", "var", "log"], .file,
                     extensions: ["log", "ips", "crash", "diag"],
                     reason: "Log do sistema sem alterações há 30 dias."),
        AdvancedRule(.xcode, .home, ["Library", "Developer", "Xcode", "DerivedData"], .directory,
                     reason: "Pasta de dados gerados pelo Xcode sem alterações há 30 dias."),
        AdvancedRule(.mailDownloads, .home,
                     ["Library", "Containers", "com.apple.mail", "Data", "Library", "Mail Downloads"],
                     .file, reason: "Cópia local em Mail Downloads sem alterações há 30 dias. Confira se foi editada."),
        AdvancedRule(.mailDownloads, .home, ["Library", "Mail Downloads"], .file,
                     reason: "Cópia local em Mail Downloads sem alterações há 30 dias. Confira se foi editada."),
        AdvancedRule(.deviceBackups, .home,
                     ["Library", "Application Support", "MobileSync", "Backup"], .directory,
                     reason: "Backup local completo sem alterações há 30 dias. Confirme que não precisa restaurá-lo."),
        AdvancedRule(.documentVersions, .home, ["Documents"], .versions, days: 0,
                     reason: "Versões locais anteriores. A remoção é permanente e preserva o documento atual."),
        AdvancedRule(.documentVersions, .home, ["Desktop"], .versions, days: 0,
                     reason: "Versões locais anteriores. A remoção é permanente e preserva o documento atual.")
    ]
}

struct AdvancedIdentity: Sendable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let size: off_t
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
        mode = info.st_mode
        size = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }

    func matches(_ info: stat) -> Bool {
        device == info.st_dev && inode == info.st_ino && mode == info.st_mode &&
        size == info.st_size && modifiedSeconds == info.st_mtimespec.tv_sec &&
        modifiedNanoseconds == info.st_mtimespec.tv_nsec &&
        changedSeconds == info.st_ctimespec.tv_sec &&
        changedNanoseconds == info.st_ctimespec.tv_nsec
    }
}

struct AdvancedCandidate: Identifiable, Sendable {
    let category: AdvancedCategory
    let url: URL
    let root: URL
    let relativePath: String
    let logicalBytes: UInt64
    let modifiedAt: Date
    let reason: String
    let identity: AdvancedIdentity
    let treeFingerprint: UInt64?
    let versionCount: Int
    var id: String { category.rawValue + ":" + url.path }
    var removesVersions: Bool { category == .documentVersions }
}

struct AdvancedResult: Sendable {
    let candidates: [AdvancedCandidate]
    let issues: [String]
}

struct AdvancedOutcome: Identifiable, Sendable {
    let candidate: AdvancedCandidate
    let destination: URL?
    let removedVersions: Bool
    let error: String?
    var id: String { candidate.id }
    var succeeded: Bool { error == nil && (destination != nil || removedVersions) }
}

struct AdvancedReport: Sendable {
    let outcomes: [AdvancedOutcome]
    var succeededCount: Int { outcomes.filter(\.succeeded).count }
}

actor AdvancedCleanupEngine {
    private let maxDepth = 24

    func analyze() throws -> AdvancedResult {
        var candidates: [AdvancedCandidate] = []
        var issues: [String] = []
        for rule in AdvancedCatalog.rules {
            try Task.checkCancellation()
            let root = try rootURL(for: rule.origin)
            let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard rootFD >= 0 else { issues.append(root.path); continue }
            defer { close(rootFD) }
            var rootInfo = stat()
            guard fstat(rootFD, &rootInfo) == 0 else { issues.append(root.path); continue }
            guard let targetFD = openDirectory(rule.path, under: rootFD, device: rootInfo.st_dev) else {
                continue
            }
            defer { close(targetFD) }
            do {
                try walk(rule, root: root, fd: targetFD, relative: rule.path,
                         device: rootInfo.st_dev, depth: 0,
                         candidates: &candidates, issues: &issues)
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(root.appendingPathComponent(rule.path.joined(separator: "/")).path) }
        }
        candidates.sort { $0.category.rawValue == $1.category.rawValue ?
            $0.logicalBytes > $1.logicalBytes : $0.category.rawValue < $1.category.rawValue }
        return AdvancedResult(candidates: candidates, issues: issues)
    }

    func execute(_ result: AdvancedResult, selectedIDs: Set<String>) throws -> AdvancedReport {
        guard !selectedIDs.isEmpty else { throw AdvancedError.emptySelection }
        let selected = result.candidates.filter { selectedIDs.contains($0.id) }
        guard selected.count == selectedIDs.count else { throw AdvancedError.invalidSelection }
        var outcomes: [AdvancedOutcome] = []
        for item in selected {
            try Task.checkCancellation()
            do {
                let rule = try matchingRule(for: item)
                let opened = try openValidated(item)
                defer { close(opened) }
                if rule.kind == .directory {
                    let tree = try measureTree(fd: opened, device: item.identity.device, depth: 0)
                    guard tree.bytes == item.logicalBytes,
                          tree.fingerprint == item.treeFingerprint,
                          tree.newest <= Date().addingTimeInterval(-rule.age) else {
                        throw AdvancedError.changed
                    }
                }
                if rule.kind == .versions {
                    let current = versionSnapshot(at: item.url)
                    guard current.count == item.versionCount, current.bytes == item.logicalBytes,
                          current.fingerprint == item.treeFingerprint else { throw AdvancedError.changed }
                    var coordinationError: NSError?
                    var removalError: Error?
                    NSFileCoordinator().coordinate(writingItemAt: item.url, options: [], error: &coordinationError) { url in
                        do {
                            var info = stat()
                            let snapshot = versionSnapshot(at: url)
                            guard lstat(url.path, &info) == 0, item.identity.matches(info),
                                  snapshot.count == item.versionCount,
                                  snapshot.fingerprint == item.treeFingerprint else {
                                throw AdvancedError.changed
                            }
                            try NSFileVersion.removeOtherVersionsOfItem(at: url)
                        }
                        catch { removalError = error }
                    }
                    if let error = coordinationError ?? removalError as NSError? { throw error }
                    outcomes.append(AdvancedOutcome(candidate: item, destination: nil,
                                                    removedVersions: true, error: nil))
                } else {
                    let destination: URL
                    if ScanScope.isFixture {
                    let trash = try ScanScope.homeDirectory().appendingPathComponent(".Trash", isDirectory: true)
                    destination = trash.appendingPathComponent(UUID().uuidString + "-" + item.url.lastPathComponent)
                    try FileManager.default.moveItem(at: item.url, to: destination)
                    } else {
                    var moved: NSURL?
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: &moved)
                    guard let moved else { throw AdvancedError.changed }
                    destination = moved as URL
                    }
                    var atDestination = stat()
                    guard lstat(destination.path, &atDestination) == 0,
                          atDestination.st_dev == item.identity.device,
                          atDestination.st_ino == item.identity.inode else { throw AdvancedError.changed }
                    outcomes.append(AdvancedOutcome(candidate: item, destination: destination,
                                                    removedVersions: false, error: nil))
                }
            } catch {
                outcomes.append(AdvancedOutcome(candidate: item, destination: nil,
                                                removedVersions: false, error: error.localizedDescription))
            }
        }
        return AdvancedReport(outcomes: outcomes)
    }

    private func rootURL(for origin: AdvancedOrigin) throws -> URL {
        let home = try ScanScope.homeDirectory()
        switch origin {
        case .home: return home
        case .system:
            return ScanScope.isFixture ? home.appendingPathComponent("SystemRoot", isDirectory: true) : URL(fileURLWithPath: "/", isDirectory: true)
        }
    }

    private func matchingRule(for item: AdvancedCandidate) throws -> AdvancedRule {
        for rule in AdvancedCatalog.rules where rule.category == item.category {
            let root = try rootURL(for: rule.origin)
            guard item.root == root else { continue }
            let parts = item.relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count > rule.path.count, Array(parts.prefix(rule.path.count)) == rule.path,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  item.url == root.appendingPathComponent(item.relativePath) else { continue }
            if rule.kind == .directory && parts.count != rule.path.count + 1 { continue }
            if rule.kind == .file && (!rule.recursive && parts.count != rule.path.count + 1) { continue }
            if rule.kind == .file, let extensions = rule.extensions,
               !extensions.contains(item.url.pathExtension.lowercased()) { continue }
            if rule.kind == .versions && !item.removesVersions { continue }
            return rule
        }
        throw AdvancedError.invalidSelection
    }

    private func openDirectory(_ components: [String], under rootFD: Int32, device: dev_t) -> Int32? {
        var fd = dup(rootFD)
        guard fd >= 0 else { return nil }
        for component in components {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            close(fd)
            guard next >= 0 else { return nil }
            var info = stat()
            guard fstat(next, &info) == 0, info.st_dev == device else { close(next); return nil }
            fd = next
        }
        return fd
    }

    private func entries(_ fd: Int32) throws -> [String] {
        let copy = dup(fd)
        guard copy >= 0, let dir = fdopendir(copy) else { if copy >= 0 { close(copy) }; throw AdvancedError.inaccessible }
        defer { closedir(dir) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        guard errno == 0 else { throw AdvancedError.inaccessible }
        return names.sorted()
    }

    private func walk(_ rule: AdvancedRule, root: URL, fd: Int32, relative: [String],
                      device: dev_t, depth: Int, candidates: inout [AdvancedCandidate],
                      issues: inout [String]) throws {
        for name in try entries(fd) {
            try Task.checkCancellation()
            let parts = relative + [name]
            let url = root.appendingPathComponent(parts.joined(separator: "/"))
            var info = stat()
            guard name.withCString({ fstatat(fd, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0,
                  info.st_dev == device else { issues.append(url.path); continue }
            let kind = info.st_mode & S_IFMT
            if kind == S_IFREG && (rule.kind == .file || rule.kind == .versions) {
                let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                guard modified <= Date().addingTimeInterval(-rule.age),
                      rule.extensions?.contains(url.pathExtension.lowercased()) ?? true else { continue }
                let fileFD = name.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
                guard fileFD >= 0 else { issues.append(url.path); continue }
                defer { close(fileFD) }
                var opened = stat()
                guard fstat(fileFD, &opened) == 0, AdvancedIdentity(info).matches(opened),
                      info.st_nlink == 1 else { issues.append(url.path); continue }
                if rule.category == .brokenPreferences {
                    guard info.st_size > 0, info.st_size <= 4 * 1024 * 1024 else { continue }
                    var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
                    let count = bytes.withUnsafeMutableBytes { pread(fileFD, $0.baseAddress, $0.count, 0) }
                    guard count == bytes.count else { issues.append(url.path); continue }
                    if (try? PropertyListSerialization.propertyList(from: Data(bytes), options: [], format: nil)) != nil { continue }
                }
                let versions = rule.kind == .versions ? versionSnapshot(at: url) : (0, UInt64(0), UInt64(0))
                if rule.kind == .versions && versions.0 == 0 { continue }
                let size = rule.kind == .versions ? versions.1 : UInt64(max(0, info.st_size))
                candidates.append(AdvancedCandidate(category: rule.category, url: url, root: root,
                                                    relativePath: parts.joined(separator: "/"),
                                                    logicalBytes: size, modifiedAt: modified,
                                                    reason: rule.reason, identity: AdvancedIdentity(info),
                                                    treeFingerprint: rule.kind == .versions ? versions.2 : nil,
                                                    versionCount: versions.0))
            } else if kind == S_IFDIR {
                let child = name.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
                guard child >= 0 else { issues.append(url.path); continue }
                defer { close(child) }
                var opened = stat()
                guard fstat(child, &opened) == 0, AdvancedIdentity(info).matches(opened) else {
                    issues.append(url.path); continue
                }
                if rule.kind == .directory {
                    do {
                        let tree = try measureTree(fd: child, device: device, depth: 0)
                        guard tree.newest <= Date().addingTimeInterval(-rule.age) else { continue }
                        candidates.append(AdvancedCandidate(category: rule.category, url: url, root: root,
                                                            relativePath: parts.joined(separator: "/"),
                                                            logicalBytes: tree.bytes,
                                                            modifiedAt: tree.newest, reason: rule.reason,
                                                            identity: AdvancedIdentity(info),
                                                            treeFingerprint: tree.fingerprint, versionCount: 0))
                    } catch { issues.append(url.path) }
                } else if depth < maxDepth && rule.recursive && !name.hasSuffix(".app") {
                    try walk(rule, root: root, fd: child, relative: parts, device: device,
                             depth: depth + 1, candidates: &candidates, issues: &issues)
                }
            }
        }
    }

    private func measureTree(fd: Int32, device: dev_t, depth: Int) throws -> (bytes: UInt64, fingerprint: UInt64, newest: Date) {
        guard depth <= maxDepth else { throw AdvancedError.inaccessible }
        var total: UInt64 = 0
        var hash: UInt64 = 14_695_981_039_346_656_037
        var newest = Date(timeIntervalSince1970: 0)
        for name in try entries(fd) {
            try Task.checkCancellation()
            var info = stat()
            guard name.withCString({ fstatat(fd, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0,
                  info.st_dev == device else { throw AdvancedError.changed }
            for byte in name.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
            for value in [UInt64(info.st_ino), UInt64(info.st_mode), UInt64(max(0, info.st_size)),
                          UInt64(info.st_mtimespec.tv_sec), UInt64(info.st_mtimespec.tv_nsec)] {
                hash = (hash ^ value) &* 1_099_511_628_211
            }
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            if modified > newest { newest = modified }
            if info.st_mode & S_IFMT == S_IFREG {
                let sum = total.addingReportingOverflow(UInt64(max(0, info.st_size)))
                total = sum.overflow ? UInt64.max : sum.partialValue
            } else if info.st_mode & S_IFMT == S_IFDIR {
                let child = name.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
                guard child >= 0 else { throw AdvancedError.inaccessible }
                defer { close(child) }
                let nested = try measureTree(fd: child, device: device, depth: depth + 1)
                let sum = total.addingReportingOverflow(nested.bytes)
                total = sum.overflow ? UInt64.max : sum.partialValue
                hash = (hash ^ nested.fingerprint) &* 1_099_511_628_211
                if nested.newest > newest { newest = nested.newest }
            }
        }
        return (total, hash, newest)
    }

    private func versionSnapshot(at url: URL) -> (count: Int, bytes: UInt64, fingerprint: UInt64) {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        if values?.isUbiquitousItem == true { return (0, 0, 0) }
        let versions = NSFileVersion.otherVersionsOfItem(at: url) ?? []
        guard !versions.contains(where: { $0.isConflict && !$0.isResolved }) else { return (0, 0, 0) }
        var bytes: UInt64 = 0
        var hash: UInt64 = 14_695_981_039_346_656_037
        for version in versions.sorted(by: { $0.url.path < $1.url.path }) {
            let size = try? version.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let amount = UInt64(max(0, size ?? 0))
            let sum = bytes.addingReportingOverflow(amount)
            bytes = sum.overflow ? UInt64.max : sum.partialValue
            for byte in version.url.path.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
            hash = (hash ^ amount) &* 1_099_511_628_211
            hash = (hash ^ UInt64(max(0, Int64(version.modificationDate?.timeIntervalSince1970 ?? 0)))) &* 1_099_511_628_211
        }
        return (versions.count, bytes, hash)
    }

    private func openValidated(_ item: AdvancedCandidate) throws -> Int32 {
        let rule = try matchingRule(for: item)
        let rootFD = open(item.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw AdvancedError.inaccessible }
        defer { close(rootFD) }
        var rootInfo = stat()
        guard fstat(rootFD, &rootInfo) == 0, rootInfo.st_dev == item.identity.device else {
            throw AdvancedError.changed
        }
        let parts = item.relativePath.split(separator: "/").map(String.init)
        guard let parent = openDirectory(Array(parts.dropLast()), under: rootFD, device: rootInfo.st_dev) else {
            throw AdvancedError.changed
        }
        defer { close(parent) }
        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC |
            (rule.kind == .directory ? O_DIRECTORY : O_NONBLOCK)
        let fd = parts.last!.withCString { openat(parent, $0, flags) }
        guard fd >= 0 else { throw AdvancedError.changed }
        var info = stat()
        var atPath = stat()
        guard fstat(fd, &info) == 0, lstat(item.url.path, &atPath) == 0,
              item.identity.matches(info), item.identity.matches(atPath),
              (info.st_mode & S_IFMT == S_IFDIR || info.st_nlink == 1) else {
            close(fd); throw AdvancedError.changed
        }
        if info.st_mode & S_IFMT == S_IFREG {
            guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { close(fd); throw AdvancedError.inaccessible }
        }
        if rule.age > 0 && rule.kind == .file {
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            guard modified <= Date().addingTimeInterval(-rule.age) else { close(fd); throw AdvancedError.changed }
        }
        return fd
    }
}

private enum AdvancedError: LocalizedError {
    case emptySelection, invalidSelection, inaccessible, changed
    var errorDescription: String? {
        switch self {
        case .emptySelection: "Selecione pelo menos um item."
        case .invalidSelection: "A seleção está fora das áreas permitidas."
        case .inaccessible: "Não foi possível acessar este item."
        case .changed: "O item mudou desde a análise. Analise novamente."
        }
    }
}
