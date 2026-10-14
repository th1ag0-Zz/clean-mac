import Foundation

@main
struct CleanupSmoke {
    static func main() async throws {
        let home = try ScanScope.homeDirectory()
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let token = UUID().uuidString
        let safe = logs.appendingPathComponent("cleanup-smoke-\(token)-safe.log")
        let changed = logs.appendingPathComponent("cleanup-smoke-\(token)-changed.log")
        let cache = home.appendingPathComponent("Library/Caches/UnknownApp/cleanup-smoke-\(token).bin")
        let installer = home.appendingPathComponent("Downloads/cleanup-smoke-\(token).dmg")
        let testTrash = trash.appendingPathComponent("cleanup-smoke-\(token)", isDirectory: true)
        let changedTrash = trash.appendingPathComponent("cleanup-smoke-\(token)-changed.txt")
        let fm = FileManager.default
        defer {
            for url in [safe, changed, cache, installer, testTrash, changedTrash] where fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }

        for url in [safe, changed, cache, installer] {
            try Data("teste\n".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -40 * 86_400)],
                                 ofItemAtPath: url.path)
        }
        let suiteName = "cleanup-mac-cleanup-smoke-\(token)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("Preferências indisponíveis") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let exclusions = AnalysisExclusions(defaults: defaults)
        let analysis = try await AnalysisEngine(exclusions: exclusions).analyze()
        let selected = Set(["Library/Logs/\(safe.lastPathComponent)",
                            "Library/Logs/\(changed.lastPathComponent)",
                            "Library/Caches/UnknownApp/\(cache.lastPathComponent)",
                            "Downloads/\(installer.lastPathComponent)"])
        let cleanup = CleanupEngine(exclusions: exclusions)
        do {
            _ = try await cleanup.makePlan(from: analysis, selectedPaths: selected.union(["Documents/keep.txt"]))
            fatalError("Seleção fora da análise aceita")
        } catch CleanupError.unknownSelection {}
        let plan = try await cleanup.makePlan(from: analysis, selectedPaths: selected)
        precondition(plan.items.count == 4)
        try Data("alterado após análise\n".utf8).write(to: changed)
        let report = try await cleanup.execute(plan)
        for outcome in report.outcomes {
            FileHandle.standardError.write(Data("\(outcome.candidate.relativePath): moved=\(outcome.moved), error=\(outcome.error ?? "-")\n".utf8))
        }
        precondition(report.movedCount == 3 && report.failedCount == 1)
        precondition(report.outcomes.first(where: { $0.candidate.url == changed })?.moved == false)
        precondition(fm.fileExists(atPath: changed.path))
        precondition(fm.fileExists(atPath: home.appendingPathComponent("Documents/keep.txt").path))
        guard let destination = report.outcomes.first(where: { $0.candidate.url == safe })?.destination else {
            fatalError("Destino ausente")
        }
        precondition(fm.fileExists(atPath: destination.path) && !fm.fileExists(atPath: safe.path))
        try fm.moveItem(at: destination, to: safe)
        for original in [cache, installer] {
            guard let moved = report.outcomes.first(where: { $0.candidate.url == original })?.destination else {
                fatalError("Cache ou instalador não foi movido")
            }
            precondition(fm.fileExists(atPath: moved.path) && !fm.fileExists(atPath: original.path))
            try fm.moveItem(at: moved, to: original)
        }

        try fm.createDirectory(at: testTrash, withIntermediateDirectories: false)
        try Data("apagar\n".utf8).write(to: testTrash.appendingPathComponent("data.txt"))
        try fm.createSymbolicLink(at: testTrash.appendingPathComponent("link.txt"),
                                  withDestinationURL: home.appendingPathComponent("Documents/keep.txt"))
        let trashEngine = TrashEngine()
        let snapshot = try await trashEngine.inspect()
        guard let item = snapshot.items.first(where: { $0.name == testTrash.lastPathComponent }) else {
            fatalError("Item de teste ausente da Lixeira")
        }
        let subset = TrashSnapshot(home: snapshot.home, rootIdentity: snapshot.rootIdentity,
                                   items: [item], issues: [])
        let deleted = try await trashEngine.empty(subset)
        precondition(deleted.deletedCount == 1 && !fm.fileExists(atPath: testTrash.path))
        precondition(fm.fileExists(atPath: home.appendingPathComponent("Documents/keep.txt").path))

        try Data("antes".utf8).write(to: changedTrash)
        let secondSnapshot = try await trashEngine.inspect()
        guard let secondItem = secondSnapshot.items.first(where: { $0.name == changedTrash.lastPathComponent }) else {
            fatalError("Segundo item de teste ausente")
        }
        try Data("depois".utf8).write(to: changedTrash)
        let changedSubset = TrashSnapshot(home: secondSnapshot.home,
                                          rootIdentity: secondSnapshot.rootIdentity,
                                          items: [secondItem], issues: [])
        let skipped = try await trashEngine.empty(changedSubset)
        precondition(skipped.failedCount == 1 && fm.fileExists(atPath: changedTrash.path))
        print("OK: seleção exata, mudança após análise, Lixeira isolada, symlink e item alterado")
    }
}
