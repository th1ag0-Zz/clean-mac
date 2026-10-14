import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ToolboxView: View {
    @State private var selectedFiles: [PermanentDeletion.Item] = []
    @State private var showingDelete = false
    @State private var showingMailOptimization = false
    @State private var showingPeriodic = false
    @State private var showingSnapshotDelete = false
    @State private var selectedSnapshot: String?
    @State private var snapshots: [String] = []
    @State private var mounts: [MountedImage] = []
    @State private var busy = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Ferramentas").font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Utilitários locais para cuidar de arquivos, discos e tela.").foregroundStyle(AppStyle.muted)
            if let result {
                Text(result).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
            }
            if busy { ProgressView("Aguardando o macOS…").tint(AppStyle.mint) }
            toolCard("Apagar arquivos definitivamente", icon: "trash.slash") {
                Text("Remove os arquivos escolhidos sem passar pela Lixeira. Em SSDs e APFS, snapshots, cópias e o gerenciamento do disco impedem garantir sobrescrita segura. Backups e cópias na nuvem não são apagados.").foregroundStyle(AppStyle.muted)
                HStack(spacing: 20) {
                    Button("Escolher arquivos…") { selectFiles() }
                    Button("Apagar \(selectedFiles.count) arquivo(s)", role: .destructive) { showingDelete = true }
                        .disabled(selectedFiles.isEmpty || busy || LocalCommand.isFixture)
                }
                ForEach(selectedFiles) { file in
                    HStack {
                        Text(file.url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Spacer()
                        Text(ByteText.format(file.bytes)).foregroundStyle(AppStyle.muted)
                        Button { selectedFiles.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle") }
                    }.font(.system(size: 12))
                }
            }
            toolCard("Imagens de disco", icon: "externaldrive") {
                Text("Monte uma imagem DMG somente para leitura e confira o conteúdo no Finder. Ao terminar, desmonte o volume aqui. Nenhum aplicativo é instalado automaticamente.").foregroundStyle(AppStyle.muted)
                Button("Abrir imagem DMG…") { selectDiskImage() }.disabled(busy || LocalCommand.isFixture)
                ForEach(mounts) { mount in
                    HStack {
                        Text(mount.path)
                        Spacer()
                        Button("Abrir no Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: mount.path)) }
                        Button("Ejetar") { detach(mount) }.disabled(busy)
                    }.font(.system(size: 12))
                }
            }
            toolCard("Otimizar índice do Mail", icon: "envelope") {
                Text("Com o Mail fechado, faz uma cópia consistente do banco de índice e compacta suas páginas SQLite. Não remove mensagens ou anexos. O acesso pode exigir Acesso Total ao Disco em Ajustes do Sistema.").foregroundStyle(AppStyle.muted)
                Button("Revisar otimização…") { showingMailOptimization = true }.disabled(busy || LocalCommand.isFixture)
            }
            if FileManager.default.isExecutableFile(atPath: "/usr/sbin/periodic") {
                toolCard("Scripts de manutenção", icon: "terminal") {
                    Text("Executa os scripts daily, weekly e monthly fornecidos pelo macOS. A autorização de administrador será solicitada pelo sistema.").foregroundStyle(AppStyle.muted)
                    Button("Executar scripts…") { showingPeriodic = true }.disabled(busy || LocalCommand.isFixture)
                }
            }
            toolCard("Verificar disco", icon: "internaldrive") {
                Text("Executa a verificação do sistema de arquivos do volume de dados, sem solicitar reparo. Pode demorar e o macOS pode exigir mais permissões.").foregroundStyle(AppStyle.muted)
                Button("Verificar volume de dados") { verifyDisk() }.disabled(busy || LocalCommand.isFixture)
            }
            toolCard("Snapshots locais do Time Machine", icon: "clock.arrow.circlepath") {
                Text("Snapshots permitem recuperar versões anteriores. O macOS costuma liberar esse espaço automaticamente. Exclua apenas um snapshot que você revisou; a exclusão é permanente e o espaço liberado pode variar.").foregroundStyle(AppStyle.muted)
                Button("Listar snapshots") { listSnapshots() }.disabled(busy || LocalCommand.isFixture)
                ForEach(snapshots, id: \.self) { name in
                    HStack {
                        Text(name).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button("Excluir…", role: .destructive) { selectedSnapshot = name; showingSnapshotDelete = true }.disabled(busy)
                    }
                }
            }
            toolCard("Limpar a tela", icon: "display") {
                Text("Mostra preto em todos os monitores para facilitar a limpeza. Pressione Esc ou clique para sair. O teclado e o trackpad continuam ativos.").foregroundStyle(AppStyle.muted)
                Button("Escurecer monitores") { ScreenCleaningController.shared.show() }.disabled(LocalCommand.isFixture)
            }
        }
        .font(.system(size: 13)).buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Otimizar o índice local do Mail?", isPresented: $showingMailOptimization) {
            Button("Criar backup e otimizar") { optimizeMail() }
        } message: {
            Text("Feche o Mail antes de continuar. Uma cópia do banco será salva em Library/Application Support/CleanMac/MailIndexBackups. O tempo varia conforme o tamanho do índice.")
        }
        .confirmationDialog("Executar manutenção periódica?", isPresented: $showingPeriodic) {
            Button("Executar scripts") { runPeriodic() }
        } message: {
            Text("O macOS pedirá autorização de administrador e executará os scripts de manutenção instalados neste Mac.")
        }
        .confirmationDialog("Apagar definitivamente \(selectedFiles.count) arquivo(s)?", isPresented: $showingDelete) {
            Button("Apagar definitivamente", role: .destructive) { deleteSelected() }
        } message: {
            Text("Os arquivos listados serão removidos sem passar pela Lixeira. Esta operação não pode ser desfeita pelo app.")
        }
        .confirmationDialog("Excluir este snapshot do Time Machine?", isPresented: $showingSnapshotDelete) {
            Button("Excluir snapshot", role: .destructive) { deleteSnapshot() }
        } message: {
            Text("\(selectedSnapshot ?? "")\nEssa versão anterior dos seus arquivos deixará de estar disponível localmente.")
        }
    }

    private func toolCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: icon).font(.system(size: 19, weight: .semibold))
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Revisar arquivos"
        guard panel.runModal() == .OK else { return }
        var rejected: [String] = []
        for url in panel.urls {
            do {
                let file = try PermanentDeletion.inspect(url)
                if !selectedFiles.contains(where: { $0.id == file.id }) { selectedFiles.append(file) }
            } catch { rejected.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if !rejected.isEmpty { result = rejected.joined(separator: "\n") }
    }

    private func deleteSelected() {
        guard !LocalCommand.isFixture, !busy else { return }
        let files = selectedFiles
        busy = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { PermanentDeletion.remove(files) }.value
            busy = false
            selectedFiles.removeAll { outcome.deletedIDs.contains($0.id) }
            result = "\(outcome.deletedIDs.count) arquivo(s) removido(s) definitivamente.\n" + outcome.errors.joined(separator: "\n")
        }
    }

    private func selectDiskImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.diskImage]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, !LocalCommand.isFixture else { return }
        busy = true
        Task {
            let output = await Task.detached(priority: .userInitiated) { LocalCommand.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-plist", url.path]) }.value
            busy = false
            guard output.status == 0 else { result = "Não foi possível montar a imagem: \(output.output)"; return }
            let mounted = MountedImage.parse(output.output)
            for mount in mounted where !mounts.contains(where: { $0.id == mount.id }) { mounts.append(mount) }
            result = mounted.isEmpty ? "A imagem foi anexada, mas não retornou um volume montado. Confira no Utilitário de Disco." : "Imagem montada somente para leitura."
        }
    }

    private func detach(_ mount: MountedImage) {
        guard !LocalCommand.isFixture, !busy else { return }
        busy = true
        Task {
            let output = await Task.detached(priority: .userInitiated) { LocalCommand.run("/usr/bin/hdiutil", ["detach", mount.device]) }.value
            busy = false
            if output.status == 0 { mounts.removeAll { $0.id == mount.id }; result = "Volume ejetado." }
            else { result = "Não foi possível ejetar o volume: \(output.output)" }
        }
    }

    private func optimizeMail() {
        guard !LocalCommand.isFixture, !busy else { return }
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.mail" && !$0.isTerminated }) else {
            result = "Feche o Mail antes de otimizar o índice."; return
        }
        busy = true
        Task {
            let outcome = await Task.detached(priority: .utility) { MailIndexOptimizer.optimize() }.value
            busy = false
            result = outcome
        }
    }

    private func runPeriodic() {
        guard !LocalCommand.isFixture, !busy, FileManager.default.isExecutableFile(atPath: "/usr/sbin/periodic") else { return }
        busy = true
        Task {
            let outcome = await Task.detached(priority: .utility) {
                LocalCommand.run("/usr/bin/osascript", ["-e", "do shell script \"/usr/sbin/periodic daily weekly monthly\" with administrator privileges"])
            }.value
            busy = false
            result = outcome.status == 0 ? "Scripts de manutenção concluídos. \(outcome.output)" : "A manutenção não foi concluída: \(outcome.output)"
        }
    }

    private func verifyDisk() {
        guard !LocalCommand.isFixture, !busy else { return }
        busy = true
        Task {
            let output = await Task.detached(priority: .utility) { LocalCommand.run("/usr/sbin/diskutil", ["verifyVolume", "/System/Volumes/Data"]) }.value
            busy = false
            result = "Verificação finalizada com código \(output.status).\n\(output.output)"
        }
    }

    private func listSnapshots() {
        guard !LocalCommand.isFixture, !busy else { return }
        busy = true
        Task {
            let output = await Task.detached(priority: .utility) { LocalCommand.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) }.value
            busy = false
            snapshots = output.output.split(whereSeparator: \.isNewline).map(String.init).filter { SnapshotName.date(from: $0) != nil }
            result = output.status != 0 ? "Não foi possível listar snapshots: \(output.output)" : "\(snapshots.count) snapshot(s) local(is) do Time Machine encontrado(s)."
        }
    }

    private func deleteSnapshot() {
        guard !LocalCommand.isFixture, !busy, let selectedSnapshot, snapshots.contains(selectedSnapshot),
              let date = SnapshotName.date(from: selectedSnapshot) else { return }
        busy = true
        Task {
            let output = await Task.detached(priority: .userInitiated) {
                LocalCommand.run("/usr/bin/osascript", ["-e", "do shell script \"/usr/bin/tmutil deletelocalsnapshots \(date)\" with administrator privileges"])
            }.value
            busy = false
            result = output.status == 0 ? "Snapshot excluído.\n\(output.output)" : "O snapshot não foi excluído: \(output.output)"
            if output.status == 0 { snapshots.removeAll { $0 == selectedSnapshot } }
        }
    }
}

@MainActor
final class ScreenCleaningController {
    static let shared = ScreenCleaningController()
    private var windows: [NSWindow] = []
    private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    func show() {
        close()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.backgroundColor = .black
            window.level = .screenSaver
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = NSHostingView(rootView: VStack(spacing: 12) {
                Text("Limpe a tela").font(.system(size: 22, weight: .medium))
                Text("Pressione Esc ou clique para sair").font(.system(size: 14))
            }.foregroundStyle(.gray).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black))
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type != .keyDown || event.keyCode == 53 { self?.close(); return nil }
            return nil
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }
    func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        for window in windows { window.close() }
        windows.removeAll()
    }
}

