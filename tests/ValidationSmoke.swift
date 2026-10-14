import Darwin
import Foundation

private struct ValidationFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct ValidationSmoke {
    static func main() async throws {
        let home = try ScanScope.homeDirectory()
        let fm = FileManager.default
        let token = UUID().uuidString
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        let unknownCache = home.appendingPathComponent("Library/Caches/UnknownApp", isDirectory: true)
        let personal = home.appendingPathComponent("Documents/keep.txt")
        let personalBefore = try Data(contentsOf: personal)
        let prefix = "validation-\(token)"
        let safe = logs.appendingPathComponent("\(prefix)-safe.log")
        let unknown = logs.appendingPathComponent("\(prefix)-unknown.data")
        let busy = logs.appendingPathComponent("\(prefix)-busy.log")
        let denied = logs.appendingPathComponent("\(prefix)-denied.log")
        let large = logs.appendingPathComponent("\(prefix)-large.log")
        let linked = logs.appendingPathComponent("\(prefix)-linked.log")
        let outsideCache = unknownCache.appendingPathComponent("\(prefix).bin")
        let backup = logs.appendingPathComponent("\(prefix)-backup.data")
        let created = [safe, unknown, busy, denied, large, linked, outsideCache, backup]
        defer {
            _ = chmod(denied.path, 0o600)
            for url in created {
                var info = stat()
                if lstat(url.path, &info) == 0 { try? fm.removeItem(at: url) }
            }
        }

        for url in [safe, unknown, busy, denied, outsideCache] {
            try oldFile(url, content: "fixture \(token)\n")
        }
        try fm.createSymbolicLink(at: linked, withDestinationURL: personal)
        let fd = open(large.path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0o600)
        try expect(fd >= 0, "Não foi possível criar o arquivo esparso")
        let largeSize: off_t = 5 * 1024 * 1024 * 1024
        let truncated = ftruncate(fd, largeSize)
        close(fd)
        try expect(truncated == 0, "Não foi possível dimensionar o arquivo esparso")
        try oldDate(large)

        let suite = "cleanup-mac-validation-\(token)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw ValidationFailure(description: "Preferências de teste indisponíveis")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let exclusions = AnalysisExclusions(defaults: defaults)
        let analysisEngine = AnalysisEngine(exclusions: exclusions)
        let cleanupEngine = CleanupEngine(exclusions: exclusions)

        let busyFD = open(busy.path, O_RDONLY | O_CLOEXEC)
        try expect(busyFD >= 0 && flock(busyFD, LOCK_EX | LOCK_NB) == 0,
                   "Não foi possível bloquear o arquivo de teste")
        defer { if busyFD >= 0 { close(busyFD) } }
        let permissionChanged = chmod(denied.path, 0o000) == 0
        try expect(permissionChanged, "Não foi possível negar a leitura do arquivo de teste")

        let first = try await analysisEngine.analyze()
        let firstPaths = Set(first.candidates.map(\.relativePath))
        try expect(firstPaths.contains(relative(safe, home: home)), "Log seguro ausente")
        try expect(firstPaths.contains(relative(large, home: home)), "Arquivo grande ausente")
        for url in [unknown, busy, denied, linked] {
            try expect(!firstPaths.contains(relative(url, home: home)), "Item indevido sugerido: \(url.path)")
        }
        try expect(firstPaths.contains(relative(outsideCache, home: home)), "Cache antigo ausente")
        try expect(first.issues.contains { $0.relativePath == relative(busy, home: home) && $0.kind == .busy },
                   "Arquivo em uso não foi reportado")
        try expect(first.issues.contains { $0.relativePath == relative(denied, home: home) && $0.kind == .inaccessible },
                   "Permissão negada não foi reportada")
        try expect(first.candidates.first(where: { $0.url == large })?.logicalBytes == UInt64(largeSize),
                   "Tamanho lógico do arquivo grande incorreto")

        _ = chmod(denied.path, 0o600)
        _ = flock(busyFD, LOCK_UN)
        let second = try await analysisEngine.analyze()
        let secondPaths = Set(second.candidates.map(\.relativePath))
        try expect(secondPaths.contains(relative(busy, home: home)), "Log desbloqueado ausente")
        try expect(secondPaths.contains(relative(denied, home: home)), "Log acessível ausente")

        let busyPlan = try await cleanupEngine.makePlan(from: second,
                                                        selectedPaths: [relative(busy, home: home)])
        try expect(flock(busyFD, LOCK_EX | LOCK_NB) == 0, "Bloqueio de execução falhou")
        let busyReport = try await cleanupEngine.execute(busyPlan)
        try expect(busyReport.failedCount == 1 && fm.fileExists(atPath: busy.path),
                   "Arquivo em uso foi movido")
        _ = flock(busyFD, LOCK_UN)

        let swapPlan = try await cleanupEngine.makePlan(from: second,
                                                        selectedPaths: [relative(safe, home: home)])
        try fm.moveItem(at: safe, to: backup)
        try fm.createSymbolicLink(at: safe, withDestinationURL: personal)
        let swapReport = try await cleanupEngine.execute(swapPlan)
        try expect(swapReport.failedCount == 1 && swapReport.movedCount == 0,
                   "Troca por link simbólico foi aceita")
        try expect(try Data(contentsOf: personal) == personalBefore,
                   "Documento pessoal foi alterado")
        try fm.removeItem(at: safe)
        try fm.moveItem(at: backup, to: safe)

        let changedPlan = try await cleanupEngine.makePlan(from: second,
                                                           selectedPaths: [relative(denied, home: home)])
        try Data("alterado\n".utf8).write(to: denied)
        let changedReport = try await cleanupEngine.execute(changedPlan)
        try expect(changedReport.failedCount == 1 && fm.fileExists(atPath: denied.path),
                   "Arquivo alterado após análise foi movido")
        try expect(try Data(contentsOf: personal) == personalBefore,
                   "Documento pessoal foi alterado")
        print("OK: catálogo, bloqueio, permissão, 5 GiB esparsos, troca de caminho e arquivo pessoal")
    }

    private static func oldFile(_ url: URL, content: String) throws {
        try Data(content.utf8).write(to: url, options: .withoutOverwriting)
        try oldDate(url)
    }

    private static func oldDate(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -40 * 86_400)],
            ofItemAtPath: url.path
        )
    }

    private static func relative(_ url: URL, home: URL) -> String {
        String(url.path.dropFirst(home.path.count + 1))
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool,
                               _ message: String) throws {
        if try !condition() { throw ValidationFailure(description: message) }
    }
}
