import Darwin
import Foundation

@main
struct ApplicationsSmoke {
    static func main() async throws {
        let home = try ScanScope.homeDirectory()
        let fm = FileManager.default
        let token = UUID().uuidString.lowercased()
        let id = "test.cleanup.\(token)"
        let orphanID = "test.orphan.\(token)"
        let app = home.appendingPathComponent("SystemRoot/Applications/Test-\(token).app")
        let changedApp = home.appendingPathComponent("SystemRoot/Applications/Changed-\(token).app")
        let data = home.appendingPathComponent("Library/Application Support/\(id)")
        let orphan = home.appendingPathComponent("Library/Caches/\(orphanID)")
        let installer = home.appendingPathComponent("Downloads/Test-\(token).dmg")
        defer {
            for url in [app, changedApp, data, orphan, installer] { try? fm.removeItem(at: url) }
        }
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": id, "CFBundleName": "Fixture App",
                               "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0"],
            format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try fm.createDirectory(at: changedApp.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let changedPlist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "test.changed.\(token)", "CFBundleName": "Changed App"],
            format: .xml, options: 0)
        try changedPlist.write(to: changedApp.appendingPathComponent("Contents/Info.plist"))
        for directory in [data, orphan] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: directory.appendingPathComponent("data.txt"))
        }
        try fm.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("installer".utf8).write(to: installer)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -40 * 86_400)],
                             ofItemAtPath: installer.path)

        let engine = ApplicationsEngine()
        let snapshot = try await engine.scan()
        guard let foundApp = snapshot.apps.first(where: { $0.bundleID == id }),
              let foundData = foundApp.associated.first(where: { $0.url.path == data.path }),
              let foundOrphan = snapshot.residues.first(where: { $0.url.path == orphan.path }),
              let foundInstaller = snapshot.installers.first(where: { $0.url.path == installer.path }) else {
            fatalError("apps=\(snapshot.apps.filter { $0.item.url.path.contains(token) }.map(\.bundleID)); data=\(snapshot.apps.flatMap(\.associated).filter { $0.url.path.contains(token) }.map(\.url.path)); residuos=\(snapshot.residues.filter { $0.url.path.contains(token) }.map(\.url.path)); instaladores=\(snapshot.installers.filter { $0.url.path.contains(token) }.map(\.url.path))")
        }
        do {
            _ = try await engine.execute(snapshot, appIDs: ["outro"], dataIDs: [],
                                         residueIDs: [], installerIDs: [])
            fatalError("Seleção desconhecida aceita")
        } catch { }
        guard let changed = snapshot.apps.first(where: { $0.item.url.path == changedApp.path }) else {
            fatalError("App para teste de alteração não encontrado")
        }
        try Data("alterado".utf8).write(to: changedApp.appendingPathComponent("Contents/Info.plist"))
        let changedReport = try await engine.execute(snapshot, appIDs: [changed.id], dataIDs: [],
                                                     residueIDs: [], installerIDs: [])
        precondition(changedReport.succeededCount == 0 && fm.fileExists(atPath: changedApp.path))
        let report = try await engine.execute(snapshot, appIDs: [foundApp.id],
                                              dataIDs: [foundData.id], residueIDs: [foundOrphan.id],
                                              installerIDs: [foundInstaller.id])
        precondition(report.outcomes.count == 4 && report.succeededCount == 4)
        precondition(!fm.fileExists(atPath: app.path) && !fm.fileExists(atPath: data.path))
        precondition(!fm.fileExists(atPath: orphan.path) && !fm.fileExists(atPath: installer.path))
        for outcome in report.outcomes {
            guard let destination = outcome.destination else { fatalError("Destino ausente") }
            try fm.moveItem(at: destination, to: URL(fileURLWithPath: outcome.path))
        }
        print("OK: apps, dados associados, resíduos, instaladores e seleção validada")
    }
}
