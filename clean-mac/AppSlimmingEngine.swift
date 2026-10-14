import Darwin
import Foundation

struct AppSlimmingLanguage: Identifiable, Sendable {
    let code: String
    let paths: [String]
    let logicalBytes: UInt64
    let mustKeep: Bool
    var id: String { code }
    var displayName: String { Locale(identifier: "pt_BR").localizedString(forLanguageCode: code) ?? code }
}

struct AppSlimmingBinary: Identifiable, Sendable {
    let relativePath: String
    let architectures: [String]
    let logicalBytes: UInt64
    let identity: AppSlimmingIdentity
    var id: String { relativePath }
}

struct AppSlimmingIdentity: Sendable {
    let device: dev_t
    let inode: ino_t
    let bytes: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    init(_ info: stat) {
        device = info.st_dev; inode = info.st_ino; bytes = info.st_size
        modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanoseconds = info.st_mtimespec.tv_nsec
    }
    func matches(_ info: stat) -> Bool {
        device == info.st_dev && inode == info.st_ino && bytes == info.st_size &&
        modifiedSeconds == info.st_mtimespec.tv_sec && modifiedNanoseconds == info.st_mtimespec.tv_nsec
    }
}

struct AppSlimmingSnapshot: Sendable {
    let source: URL
    let sourceIdentity: AppSlimmingIdentity
    let languages: [AppSlimmingLanguage]
    let binaries: [AppSlimmingBinary]
    let logicalBytes: UInt64
    let nativeArchitecture: String
    let scannedFiles: Int
    let notes: [String]
    var universalBinaries: [AppSlimmingBinary] { binaries.filter { $0.architectures.count > 1 && $0.architectures.contains(nativeArchitecture) } }
}

struct AppSlimmingResult: Sendable {
    let copyURL: URL
    let beforeBytes: UInt64
    let afterBytes: UInt64
    let removedLanguageCount: Int
    let thinnedBinaryCount: Int
    var savedBytes: UInt64 { beforeBytes > afterBytes ? beforeBytes - afterBytes : 0 }
}

enum AppSlimmingError: LocalizedError {
    case unsafe(String), changed, limit, command(String), incompleteCopy(URL, String)
    var errorDescription: String? {
        switch self {
        case .unsafe(let reason): reason
        case .changed: "O app mudou desde a análise. Analise novamente."
        case .limit: "O app ultrapassa o limite de 100.000 entradas ou 2.000 binários. Nenhuma cópia foi criada."
        case .command(let reason): reason
        case .incompleteCopy(let url, let reason): "A otimização não foi concluída: \(reason) A cópia parcial está em \(url.path). O original foi preservado."
        }
    }
}

actor AppSlimmingEngine {
    private let manager = FileManager.default
    private static let maximumEntries = 100_000
    private static let maximumBinaries = 2_000
    private struct Inventory {
        var bytes: UInt64 = 0
        var files = 0
        var languagePaths: [String: [String]] = [:]
        var languageBytes: [String: UInt64] = [:]
        var binaries: [AppSlimmingBinary] = []
        var notes: [String] = []
        var developmentLanguages: Set<String> = []
    }

    func scan(_ source: URL) throws -> AppSlimmingSnapshot {
        try Self.validateDirectory(source, sourceApp: true)
        var info = stat()
        guard lstat(source.path, &info) == 0 else { throw AppSlimmingError.changed }
        let identity = AppSlimmingIdentity(info)
        let inventory = try inventory(source, inspectBinaries: true)
        let required = Set((["Base", "en", "English"] + Locale.preferredLanguages + inventory.developmentLanguages.sorted()).flatMap(Self.languageAliases))
        let languages = inventory.languagePaths.map { code, paths in
            AppSlimmingLanguage(code: code, paths: paths.sorted(), logicalBytes: inventory.languageBytes[code] ?? 0,
                                mustKeep: !Set(Self.languageAliases(code)).isDisjoint(with: required))
        }.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
        return AppSlimmingSnapshot(source: source, sourceIdentity: identity, languages: languages,
                                   binaries: inventory.binaries, logicalBytes: inventory.bytes,
                                   nativeArchitecture: Self.nativeArchitecture, scannedFiles: inventory.files, notes: inventory.notes)
    }

    func createCopy(_ snapshot: AppSlimmingSnapshot, omitting languages: Set<String>, thinArchitectures: Bool,
                    outputFolder: URL) throws -> AppSlimmingResult {
        try Self.validateDirectory(snapshot.source, sourceApp: true)
        try Self.validateDirectory(outputFolder, sourceApp: false)
        guard outputFolder.path != snapshot.source.path, !outputFolder.path.hasPrefix(snapshot.source.path + "/") else {
            throw AppSlimmingError.unsafe("Escolha uma pasta de destino fora do app original.")
        }
        var original = stat()
        guard lstat(snapshot.source.path, &original) == 0, snapshot.sourceIdentity.matches(original),
              languages.isSubset(of: Set(snapshot.languages.filter { !$0.mustKeep }.map(\.code))) else { throw AppSlimmingError.changed }
        let name = snapshot.source.deletingPathExtension().lastPathComponent
        let destination = outputFolder.appendingPathComponent("\(name) - Otimizado \(UUID().uuidString.prefix(8)).app", isDirectory: true)
        guard !manager.fileExists(atPath: destination.path) else { throw AppSlimmingError.unsafe("O destino já existe.") }
        // Validate all internal links before copying: absolute or escaping links could sign files outside the copy.
        _ = try inventory(snapshot.source, inspectBinaries: false)
        do {
            try manager.copyItem(at: snapshot.source, to: destination)
            try Self.validateDirectory(destination, sourceApp: false)
            let before = try inventory(destination, inspectBinaries: false).bytes
            var omittedPaths: [String] = []
            for language in snapshot.languages where languages.contains(language.code) {
                for relative in language.paths {
                    try Task.checkCancellation()
                    if omittedPaths.contains(where: { relative.hasPrefix($0 + "/") }) { continue }
                    let resource = try Self.child(relative, in: destination)
                    guard resource.pathExtension == "lproj" else { throw AppSlimmingError.changed }
                    try manager.removeItem(at: resource)
                    omittedPaths.append(relative)
                }
            }
            var thinned = 0
            if thinArchitectures {
                for binary in snapshot.universalBinaries {
                    try Task.checkCancellation()
                    // Language resources may themselves contain executable files, already omitted above.
                    if snapshot.languages.filter({ languages.contains($0.code) }).flatMap(\.paths).contains(where: { binary.relativePath.hasPrefix($0 + "/") }) { continue }
                    let sourceBinary = try Self.child(binary.relativePath, in: snapshot.source)
                    var current = stat()
                    guard lstat(sourceBinary.path, &current) == 0, binary.identity.matches(current) else { throw AppSlimmingError.changed }
                    let copied = try Self.child(binary.relativePath, in: destination)
                    let temporary = copied.deletingLastPathComponent().appendingPathComponent(".slimming-\(UUID().uuidString)")
                    _ = try run("/usr/bin/lipo", [copied.path, "-thin", snapshot.nativeArchitecture, "-output", temporary.path], timeout: 30)
                    let permissions = try manager.attributesOfItem(atPath: copied.path)[.posixPermissions]
                    if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path) }
                    // Both paths are inside a fresh copy, with ancestors checked immediately before replacement.
                    _ = try Self.child(binary.relativePath, in: destination)
                    try manager.removeItem(at: copied)
                    try manager.moveItem(at: temporary, to: copied)
                    thinned += 1
                }
            }
            _ = try inventory(destination, inspectBinaries: false)
            _ = try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", destination.path], timeout: 120)
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", destination.path], timeout: 60)
            let after = try inventory(destination, inspectBinaries: false).bytes
            return AppSlimmingResult(copyURL: destination, beforeBytes: before, afterBytes: after,
                                     removedLanguageCount: languages.count, thinnedBinaryCount: thinned)
        } catch { throw AppSlimmingError.incompleteCopy(destination, error.localizedDescription) }
    }

    private func inventory(_ root: URL, inspectBinaries: Bool) throws -> Inventory {
        var result = Inventory()
        var enumerationError: Error?
        guard let entries = manager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw AppSlimmingError.changed }
        var visited = 0
        for case let url as URL in entries {
            try Task.checkCancellation()
            visited += 1
            guard visited <= Self.maximumEntries else { throw AppSlimmingError.limit }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw AppSlimmingError.changed }
            guard try url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem != true else {
                throw AppSlimmingError.unsafe("O app contém recursos armazenados na nuvem. Faça uma cópia local completa antes de continuar.")
            }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK {
                let target = try manager.destinationOfSymbolicLink(atPath: url.path)
                guard !target.hasPrefix("/"), Self.canonicalPath(url)?.hasPrefix(root.path + "/") == true else {
                    throw AppSlimmingError.unsafe("O app contém um link absoluto ou externo: \(url.lastPathComponent). Não é seguro assinar uma cópia automaticamente.")
                }
                // DirectoryEnumerator does not traverse symlinks. Calling skipDescendants
                // for a leaf link can suppress its next sibling directory (Versions/A).
                continue
            }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            if type == S_IFDIR, url.pathExtension == "lproj" {
                result.languagePaths[url.deletingPathExtension().lastPathComponent, default: []].append(relative)
            }
            guard type == S_IFREG, info.st_size >= 0 else { continue }
            result.files += 1
            let bytes = UInt64(info.st_size)
            result.bytes = Self.add(result.bytes, bytes)
            if url.lastPathComponent == "Info.plist", bytes <= 1_048_576,
               let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let development = plist["CFBundleDevelopmentRegion"] as? String {
                result.developmentLanguages.insert(development)
            }
            if let resource = relative.split(separator: "/").first(where: { $0.hasSuffix(".lproj") }) {
                let code = String(resource.dropLast(6))
                result.languageBytes[code] = Self.add(result.languageBytes[code] ?? 0, bytes)
            }
            if inspectBinaries, try Self.isMachO(url) {
                guard result.binaries.count < Self.maximumBinaries else { throw AppSlimmingError.limit }
                do {
                    let output = try run("/usr/bin/lipo", ["-archs", url.path], timeout: 10)
                    let architectures = output.split(whereSeparator: \.isWhitespace).map(String.init)
                    guard !architectures.isEmpty else { throw AppSlimmingError.command("lipo não informou arquiteturas para \(relative).") }
                    result.binaries.append(AppSlimmingBinary(relativePath: relative, architectures: architectures,
                                                            logicalBytes: bytes, identity: AppSlimmingIdentity(info)))
                } catch { result.notes.append("Não foi possível inspecionar \(relative): \(error.localizedDescription)") }
            }
        }
        if let enumerationError { throw enumerationError }
        return result
    }

    private static func validateDirectory(_ url: URL, sourceApp: Bool) throws {
        if ScanScope.isFixture {
            let fixture = try ScanScope.homeDirectory()
            guard url.path.hasPrefix(fixture.path + "/") else {
                throw AppSlimmingError.unsafe("Em testes, origem e destino devem ficar dentro da home de fixture validada.")
            }
        }
        guard !url.pathComponents.contains(".."), !url.pathComponents.contains("."), Self.canonicalPath(url) == url.path,
              url.path != "/", (!sourceApp || url.pathExtension.lowercased() == "app") else { throw AppSlimmingError.unsafe("Selecione um app ou uma pasta local sem links no caminho.") }
        let blocked = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private/var", "/private/etc"]
        guard !blocked.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else { throw AppSlimmingError.unsafe("Apps e pastas do sistema não podem ser otimizados.") }
        let cloud = ["dropbox", "onedrive", "google drive", "googledrive", "cloudstorage", "mobile documents", "icloud", "pcloud"]
        var ancestor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            ancestor.appendPathComponent(component)
            var info = stat()
            guard lstat(ancestor.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  !cloud.contains(where: { component.lowercased().contains($0) }), component.lowercased() != "box" else { throw AppSlimmingError.unsafe("O caminho deve ser uma pasta local, sem links e fora da nuvem.") }
            let values = try ancestor.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsLocalKey])
            guard values.isUbiquitousItem != true, values.volumeIsLocal == true else { throw AppSlimmingError.unsafe("Pastas na nuvem e volumes de rede não são suportados.") }
        }
        if sourceApp {
            let values = try url.resourceValues(forKeys: [.isSystemImmutableKey])
            guard values.isSystemImmutable != true else { throw AppSlimmingError.unsafe("Este app tem proteção do sistema.") }
        }
    }

    private static func child(_ relative: String, in root: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw AppSlimmingError.changed }
        let url = root.appendingPathComponent(relative)
        guard url.path.hasPrefix(root.path + "/"), Self.canonicalPath(url) == url.path else { throw AppSlimmingError.changed }
        return url
    }
    private static func canonicalPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
    private static func isMachO(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = [UInt8](try handle.read(upToCount: 4) ?? Data())
        return [[0xfe,0xed,0xfa,0xce], [0xce,0xfa,0xed,0xfe], [0xfe,0xed,0xfa,0xcf], [0xcf,0xfa,0xed,0xfe], [0xca,0xfe,0xba,0xbe], [0xbe,0xba,0xfe,0xca], [0xca,0xfe,0xba,0xbf], [0xbf,0xba,0xfe,0xca]].contains(bytes)
    }
    private static func languageAliases(_ code: String) -> [String] {
        let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let legacy = ["english": "en", "portuguese": "pt", "french": "fr", "german": "de", "spanish": "es", "italian": "it", "japanese": "ja", "dutch": "nl", "korean": "ko", "russian": "ru", "chinese": "zh"]
        if let language = legacy[normalized] { return [normalized, language] }
        return [normalized, normalized.split(separator: "-").first.map(String.init) ?? normalized]
    }
    private static var nativeArchitecture: String {
        var supported: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &supported, &size, nil, 0) == 0, supported == 1 { return "arm64" }
        return "x86_64"
    }
    private static func add(_ first: UInt64, _ second: UInt64) -> UInt64 {
        let sum = first.addingReportingOverflow(second)
        return sum.overflow ? UInt64.max : sum.partialValue
    }
    private func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> String {
        guard manager.isExecutableFile(atPath: executable) else { throw AppSlimmingError.command("Ferramenta indisponível: \(executable).") }
        let log = manager.temporaryDirectory.appendingPathComponent("app-slimming-log-\(UUID().uuidString)")
        guard manager.createFile(atPath: log.path, contents: nil) else { throw AppSlimmingError.command("Não foi possível criar o registro temporário.") }
        defer { try? manager.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date.now > deadline {
                process.terminate()
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                if Task.isCancelled { throw CancellationError() }
                throw AppSlimmingError.command("\(URL(fileURLWithPath: executable).lastPathComponent) excedeu o tempo limite.")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        let reader = try FileHandle(forReadingFrom: log)
        defer { try? reader.close() }
        let output = String(decoding: try reader.read(upToCount: 16_384) ?? Data(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw AppSlimmingError.command(output.isEmpty ? "\(executable) falhou (\(process.terminationStatus))." : output) }
        return output
    }
}
