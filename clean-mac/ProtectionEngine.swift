import AppKit
import CryptoKit
import Darwin
import Foundation
import SQLite3

struct ProtectionFinding: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let path: String
    let attention: Bool
}

struct BrowserTrace: Identifiable, Sendable {
    let url: URL
    let browser: String
    let bundleID: String
    let kind: String
    let bytes: UInt64
    let identity: ProtectionIdentity
    let fingerprint: Data
    var id: String { url.path }
}

struct ProtectionIdentity: Sendable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let seconds: Int64
    let nanoseconds: Int64
    let changeSeconds: Int64
    let changeNanoseconds: Int64
    init(_ value: stat) {
        device = value.st_dev; inode = value.st_ino; size = value.st_size
        seconds = Int64(value.st_mtimespec.tv_sec); nanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changeSeconds = Int64(value.st_ctimespec.tv_sec); changeNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }
    func matches(_ value: stat) -> Bool {
        value.st_dev == device && value.st_ino == inode && value.st_size == size &&
        value.st_mtimespec.tv_sec == seconds && value.st_mtimespec.tv_nsec == nanoseconds &&
        value.st_ctimespec.tv_sec == changeSeconds && value.st_ctimespec.tv_nsec == changeNanoseconds
    }
}

struct ProtectionSnapshot: Sendable {
    let home: URL
    let findings: [ProtectionFinding]
    let traces: [BrowserTrace]
    let permissions: [ProtectionFinding]
    let security: [ProtectionFinding]
    let issues: [String]
    let scannedFiles: Int
    let scanRoot: URL
    let scannerReport: String
}

struct ProtectionTrashOutcome: Identifiable, Sendable {
    let id: String
    let destination: URL?
    let error: String?
}

enum ProtectionError: LocalizedError {
    case unsafePath, changed, tooLarge, inaccessible, browserOpen(String)
    var errorDescription: String? {
        switch self {
        case .unsafePath: "Caminho ou ancestral simbólico recusado."
        case .changed: "Arquivo mudou desde a análise; analise novamente."
        case .tooLarge: "Arquivo excede o limite desta análise local."
        case .inaccessible: "Arquivo indisponível ou sem permissão de leitura."
        case .browserOpen(let name): "Feche totalmente o \(name) antes de limpar seus rastros."
        }
    }
}

actor ProtectionEngine {
    // Public test string; this is a scanner integrity test, never a malware signature database.
    static let eicar = Data("X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*".utf8)
    private let scanFileLimit = 3_000
    private let fileByteLimit = 8 * 1_024 * 1_024
    private let scanByteLimit = 64 * 1_024 * 1_024
    private let traceByteLimit = 256 * 1_024 * 1_024

    func analyze(folder: URL? = nil) throws -> ProtectionSnapshot {
        let home = try ScanScope.homeDirectory()
        let isFixture = home != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let root = folder ?? home.appendingPathComponent("Downloads", isDirectory: true)
        guard root.standardizedFileURL.path == root.path, root.resolvingSymlinksInPath().path == root.path else { throw ProtectionError.unsafePath }
        var findings: [ProtectionFinding] = []
        var issues: [String] = []
        auditPersistence(home: home, isFixture: isFixture, findings: &findings, issues: &issues)
        var count = 0
        var visited = 0
        var total = 0
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants], errorHandler: { url, _ in
            issues.append("Sem acesso: \(url.path)"); return true
        }) {
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                if visited >= scanFileLimit || total >= scanByteLimit { issues.append("Varredura limitada a 3.000 itens e 64 MB; há itens não verificados."); break }
                visited += 1
                let depth = url.pathComponents.count - root.pathComponents.count
                if depth > 20 { enumerator.skipDescendants(); continue }
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
                if values.isDirectory == true { continue }
                do {
                    let (_, data) = try readRegular(url, maxBytes: min(fileByteLimit, scanByteLimit - total))
                    count += 1; total += data.count
                    if data.range(of: Self.eicar) != nil {
                        findings.append(ProtectionFinding(title: "Arquivo de teste EICAR", detail: "Assinatura pública de teste detectada. Este resultado verifica a leitura do scanner e não identifica uma ameaça real.", path: url.path, attention: true))
                    }
                } catch { issues.append("Não verificado: \(url.path) — \(error.localizedDescription)") }
            }
        } else { issues.append("Pasta de varredura indisponível: \(root.path)") }
        let traces = inspectBrowserTraces(home: home, issues: &issues)
        let permissions = auditPermissions(home: home, issues: &issues)
        let security = isFixture ? [] : securityStatus()
        let scanner = isFixture ? "Scanner externo desativado na fixture." : runLocalScanner(root: root)
        return ProtectionSnapshot(home: home, findings: findings, traces: traces, permissions: permissions,
                                  security: security, issues: Array(issues.prefix(100)), scannedFiles: count,
                                  scanRoot: root, scannerReport: scanner)
    }

    func trashTraces(_ snapshot: ProtectionSnapshot, selectedIDs: Set<String>) async throws -> [ProtectionTrashOutcome] {
        let home = try ScanScope.homeDirectory()
        guard home == snapshot.home else { throw ProtectionError.changed }
        let isFixture = home != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let running: Set<String> = isFixture ? [] : await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        // Keep SQLite databases and their journal files together. Reinspect for new files
        // created since review before moving any member of a browser's set.
        var freshIssues: [String] = []
        let fresh = inspectBrowserTraces(home: home, issues: &freshIssues)
        let selectedBrowsers = Set(snapshot.traces.filter { selectedIDs.contains($0.id) }.map(\.bundleID))
        for browser in selectedBrowsers {
            let expected = Set(snapshot.traces.filter { $0.bundleID == browser }.map(\.id))
            let current = Set(fresh.filter { $0.bundleID == browser }.map(\.id))
            guard expected == current, expected.isSubset(of: selectedIDs), freshIssues.isEmpty else { throw ProtectionError.changed }
            for trace in snapshot.traces where trace.bundleID == browser {
                guard let now = fresh.first(where: { $0.id == trace.id }),
                      trace.fingerprint == now.fingerprint,
                      trace.identity.inode == now.identity.inode,
                      trace.identity.seconds == now.identity.seconds,
                      trace.identity.nanoseconds == now.identity.nanoseconds,
                      trace.identity.changeSeconds == now.identity.changeSeconds,
                      trace.identity.changeNanoseconds == now.identity.changeNanoseconds else { throw ProtectionError.changed }
            }
        }
        var outcomes: [ProtectionTrashOutcome] = []
        for trace in snapshot.traces where selectedIDs.contains(trace.id) {
            try Task.checkCancellation()
            do {
                guard !running.contains(trace.bundleID) else { throw ProtectionError.browserOpen(trace.browser) }
                guard trace.url.path.hasPrefix(home.path + "/Library/") else { throw ProtectionError.unsafePath }
                let (identity, data) = try readRegular(trace.url, maxBytes: traceByteLimit)
                guard trace.identity.device == identity.device, trace.identity.inode == identity.inode,
                      trace.identity.seconds == identity.seconds, trace.identity.nanoseconds == identity.nanoseconds,
                      trace.identity.changeSeconds == identity.changeSeconds, trace.identity.changeNanoseconds == identity.changeNanoseconds,
                      trace.identity.size == identity.size,
                      Data(SHA256.hash(data: data)) == trace.fingerprint else { throw ProtectionError.changed }
                let (parent, name) = try openParent(trace.url)
                defer { close(parent) }
                var current = stat()
                guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0, trace.identity.matches(current) else { throw ProtectionError.changed }
                let trash = home.appendingPathComponent(".Trash", isDirectory: true)
                let (homeFD, trashName) = try openParent(trash)
                defer { close(homeFD) }
                if mkdirat(homeFD, trashName, 0o700) != 0 && errno != EEXIST { throw ProtectionError.inaccessible }
                let trashFD = openat(homeFD, trashName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard trashFD >= 0 else { throw ProtectionError.unsafePath }
                defer { close(trashFD) }
                // Descriptor based rename keeps the source anchored to the reviewed parent.
                let destinationName = "\(UUID().uuidString)-\(name)"
                guard renameat(parent, name, trashFD, destinationName) == 0 else { throw ProtectionError.inaccessible }
                outcomes.append(ProtectionTrashOutcome(id: trace.id, destination: trash.appendingPathComponent(destinationName), error: nil))
            } catch { outcomes.append(ProtectionTrashOutcome(id: trace.id, destination: nil, error: error.localizedDescription)) }
        }
        return outcomes
    }

    private func auditPersistence(home: URL, isFixture: Bool, findings: inout [ProtectionFinding], issues: inout [String]) {
        let system = isFixture ? home.appendingPathComponent("SystemRoot/Library") : URL(fileURLWithPath: "/Library")
        let roots = [home.appendingPathComponent("Library/LaunchAgents"), system.appendingPathComponent("LaunchAgents"), system.appendingPathComponent("LaunchDaemons")]
        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for url in urls.prefix(1_000) where url.pathExtension == "plist" {
                do {
                    let (_, data) = try readRegular(url, maxBytes: 1_024 * 1_024)
                    guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
                    let arguments = plist["ProgramArguments"] as? [String] ?? []
                    let executable = plist["Program"] as? String ?? arguments.first ?? "(sem executável)"
                    var reasons: [String] = []
                    if executable.hasPrefix("/tmp/") || executable.hasPrefix("/private/tmp/") || executable.contains("/Downloads/") || executable.contains("/.Trash/") { reasons.append("executável em pasta transitória") }
                    if arguments.contains(where: { ["curl", "wget", "osascript"].contains(URL(fileURLWithPath: $0).lastPathComponent) }) || arguments.contains(where: { $0.contains("base64") || $0.contains("curl ") || $0.contains("wget ") }) { reasons.append("comando de download ou automação; revise o conteúdo") }
                    if plist["RunAtLoad"] as? Bool == true { reasons.append("executa ao iniciar sessão") }
                    let attention = reasons.contains(where: { !$0.hasPrefix("executa ao") })
                    findings.append(ProtectionFinding(title: plist["Label"] as? String ?? url.lastPathComponent,
                        detail: "\(executable)\n\(reasons.isEmpty ? "Persistência local encontrada; sua presença não prova atividade maliciosa." : reasons.joined(separator: "; "))",
                        path: url.path, attention: attention))
                } catch { issues.append("Persistência não lida: \(url.path)") }
            }
        }
    }

    private func inspectBrowserTraces(home: URL, issues: inout [String]) -> [BrowserTrace] {
        var candidates: [(URL, String, String, String)] = []
        let safari = [("Library/Safari/History.db", "Histórico"), ("Library/Cookies/Cookies.binarycookies", "Cookies"), ("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies", "Cookies")]
        for (path, kind) in safari { candidates.append((home.appendingPathComponent(path), "Safari", "com.apple.Safari", kind)) }
        let chromium = [("Google/Chrome", "Chrome", "com.google.Chrome"), ("Microsoft Edge", "Edge", "com.microsoft.edgemac"), ("BraveSoftware/Brave-Browser", "Brave", "com.brave.Browser")]
        for (path, browser, bundle) in chromium {
            let base = home.appendingPathComponent("Library/Application Support/\(path)")
            let profiles = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            for profile in profiles.prefix(100) where profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile ") {
                for (name, kind) in [("History", "Histórico"), ("Cookies", "Cookies"), ("Network/Cookies", "Cookies")] { candidates.append((profile.appendingPathComponent(name), browser, bundle, kind)) }
            }
        }
        let firefox = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        for profile in ((try? FileManager.default.contentsOfDirectory(at: firefox, includingPropertiesForKeys: nil)) ?? []).prefix(100) {
            // places.sqlite also contains bookmarks, so it is deliberately not a cleanup candidate.
            candidates.append((profile.appendingPathComponent("cookies.sqlite"), "Firefox", "org.mozilla.firefox", "Cookies"))
        }
        var result: [BrowserTrace] = []
        for (url, browser, bundle, kind) in candidates {
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let item = URL(fileURLWithPath: url.path + suffix)
                guard FileManager.default.fileExists(atPath: item.path) else { continue }
                do {
                    let (identity, data) = try readRegular(item, maxBytes: traceByteLimit)
                    result.append(BrowserTrace(url: item, browser: browser, bundleID: bundle, kind: suffix.isEmpty ? kind : "\(kind) · auxiliar \(suffix)", bytes: UInt64(data.count), identity: identity, fingerprint: Data(SHA256.hash(data: data))))
                } catch { issues.append("Rastro não lido: \(item.path) — \(error.localizedDescription)") }
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    private func auditPermissions(home: URL, issues: inout [String]) -> [ProtectionFinding] {
        let url = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        do { let (fd, _) = try openParent(url); close(fd) }
        catch { issues.append("Permissões: banco TCC indisponível. Consulte Privacidade e Segurança nos Ajustes."); return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            issues.append("Permissões: macOS não permitiu ler o TCC. Conceda Acesso Total ao Disco ou consulte os Ajustes.")
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT service, client, auth_value FROM access ORDER BY service, client LIMIT 400", -1, &statement, nil) == SQLITE_OK else {
            issues.append("Formato do TCC não suportado; use os Ajustes do Sistema."); return []
        }
        defer { sqlite3_finalize(statement) }
        var result: [ProtectionFinding] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let serviceText = sqlite3_column_text(statement, 0), let clientText = sqlite3_column_text(statement, 1) else { continue }
            let service = String(cString: serviceText)
            let client = String(cString: clientText)
            let value = sqlite3_column_int(statement, 2)
            let status = value == 2 ? "Permitido" : value == 0 ? "Negado" : value == 3 ? "Limitado" : "Indeterminado (\(value))"
            result.append(ProtectionFinding(title: client, detail: "\(service.replacingOccurrences(of: "kTCCService", with: "")) · \(status)", path: "", attention: false))
        }
        issues.append("Permissões: somente TCC do usuário, até 400 registros; decisões do sistema e permissões temporárias podem não aparecer.")
        return result
    }

    private func securityStatus() -> [ProtectionFinding] {
        [("Gatekeeper", "/usr/sbin/spctl", ["--status"]), ("FileVault", "/usr/bin/fdesetup", ["status"]), ("Firewall", "/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])].map { title, path, arguments in
            let result = command(path, arguments: arguments, timeout: 8)
            return ProtectionFinding(title: title, detail: result.output.isEmpty ? "Status indisponível (\(result.code))." : result.output, path: "", attention: false)
        }
    }

    private func runLocalScanner(root: URL) -> String {
        guard let scanner = ["/opt/homebrew/bin/clamscan", "/usr/local/bin/clamscan", "/usr/bin/clamscan"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return "ClamAV não instalado. A verificação integrada reconhece somente EICAR e sinais de persistência; não substitui um antivírus."
        }
        let databases = ["/opt/homebrew/var/lib/clamav", "/usr/local/var/lib/clamav", "/var/lib/clamav"]
        guard let database = databases.first(where: { path in
            ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).contains { ["cvd", "cld"].contains(URL(fileURLWithPath: $0).pathExtension) }
        }) else { return "ClamAV encontrado, mas sem assinaturas locais. Instale uma base de assinaturas para habilitar a análise; este app não baixa atualizações." }
        let result = command(scanner, arguments: ["--database=\(database)", "--recursive", "--infected", "--max-files=3000", "--max-filesize=8M", "--max-scansize=64M", "--max-recursion=20", "--", root.path], timeout: 90)
        let status = result.code == 0 ? "ClamAV não encontrou assinaturas conhecidas nos arquivos examinados." : result.code == 1 ? "ClamAV encontrou uma ou mais assinaturas: revise os resultados." : "ClamAV não concluiu a análise (código \(result.code))."
        return "\(status)\nBase local: \(database). Sem atualização de assinaturas pela rede. Limites por arquivo de 8 MB, 64 MB por objeto e 3.000 arquivos por arquivo compactado; máximo de 90 segundos.\n\(result.output)"
    }

    private func command(_ path: String, arguments: [String], timeout: TimeInterval) -> (code: Int32, output: String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do {
            try process.run(); pipe.fileHandleForWriting.closeFile()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); watchdog.cancel()
            return (process.terminationStatus, String(decoding: data.prefix(32_768), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { return (-1, error.localizedDescription) }
    }

    private func openParent(_ url: URL) throws -> (Int32, String) {
        let normalized = url.standardizedFileURL
        guard normalized.path == url.path, normalized.path == normalized.resolvingSymlinksInPath().path else { throw ProtectionError.unsafePath }
        let parts = normalized.pathComponents.filter { $0 != "/" }
        guard let name = parts.last, !name.isEmpty else { throw ProtectionError.unsafePath }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ProtectionError.inaccessible }
        for component in parts.dropLast() {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw ProtectionError.unsafePath }
            fd = next
        }
        return (fd, name)
    }

    private func readRegular(_ url: URL, maxBytes: Int) throws -> (ProtectionIdentity, Data) {
        let (parent, name) = try openParent(url); defer { close(parent) }
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw ProtectionError.inaccessible }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw ProtectionError.unsafePath }
        guard info.st_size >= 0, info.st_size <= maxBytes else { throw ProtectionError.tooLarge }
        let identity = ProtectionIdentity(info)
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count >= 0 else { throw ProtectionError.inaccessible }
            if count == 0 { break }
            guard data.count + count <= maxBytes else { throw ProtectionError.tooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard fstat(fd, &info) == 0, identity.matches(info) else { throw ProtectionError.changed }
        return (identity, data)
    }
}
