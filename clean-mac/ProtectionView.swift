import AppKit
import Combine
import SwiftUI

@MainActor
final class ProtectionViewModel: ObservableObject {
    static let shared = ProtectionViewModel()
    @Published var snapshot: ProtectionSnapshot?
    @Published var selectedBrowsers = Set<String>() {
        didSet { if selectedBrowsers.isEmpty && pendingAutomaticScan { scheduleAutomaticScan() } }
    }
    @Published var folder: URL?
    @Published var busy = false
    @Published var message: String?
    @Published private(set) var monitoredFolder: URL?
    @Published private(set) var lastObservedChange: Date?
    @Published private(set) var lastAudit: Date?
    @Published private(set) var pendingAutomaticScan = false
    private let engine = ProtectionEngine()
    private var task: Task<Void, Never>?
    private var monitor: ProtectionFolderMonitor?
    private var rescanTask: Task<Void, Never>?
    private var lastScanStarted = Date.distantPast
    private var scopeGranted = false
    var monitoring: Bool { monitoredFolder != nil }

    var selectedTraces: [BrowserTrace] {
        snapshot?.traces.filter { selectedBrowsers.contains($0.bundleID) } ?? []
    }

    func scan() { performScan(automatic: false) }

    private func performScan(automatic: Bool) {
        guard !busy else { return }
        rescanTask?.cancel(); rescanTask = nil; pendingAutomaticScan = false
        busy = true; message = nil; selectedBrowsers = []; snapshot = nil
        lastScanStarted = Date()
        let folder = folder
        task = Task {
            let allowed = folder?.startAccessingSecurityScopedResource() ?? false
            defer {
                if allowed { folder?.stopAccessingSecurityScopedResource() }
                busy = false
                if pendingAutomaticScan { scheduleAutomaticScan() }
            }
            do {
                let result = try await engine.analyze(folder: folder)
                try Task.checkCancellation()
                snapshot = result
                lastAudit = Date()
                if automatic { message = "Auditoria local atualizada após alterações na pasta monitorada. Revise os resultados; nenhuma limpeza foi executada." }
            }
            catch is CancellationError { message = "Análise cancelada." }
            catch { message = error.localizedDescription }
        }
    }

    func cancel() { task?.cancel() }

    func startMonitoring() {
        guard !monitoring, !busy else { return }
        do {
            let home = try ScanScope.homeDirectory()
            let root = folder ?? home.appendingPathComponent("Downloads", isDirectory: true)
            guard root.path == root.standardizedFileURL.path, root.path == root.resolvingSymlinksInPath().path,
                  !ScanScope.isFixture || root.path.hasPrefix(home.path + "/") else { throw ProtectionError.unsafePath }
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw ProtectionError.inaccessible }
            scopeGranted = root.startAccessingSecurityScopedResource()
            do {
                monitor = try ProtectionFolderMonitor(root: root) { [weak self] in
                    Task { @MainActor [weak self] in self?.folderChanged() }
                }
            } catch {
                if scopeGranted { root.stopAccessingSecurityScopedResource() }; scopeGranted = false
                throw error
            }
            monitoredFolder = root; lastObservedChange = nil
            scan()
        } catch { message = "Não foi possível monitorar: \(error.localizedDescription)" }
    }

    func stopMonitoring() {
        rescanTask?.cancel(); rescanTask = nil; pendingAutomaticScan = false
        monitor?.stop(); monitor = nil
        if scopeGranted { monitoredFolder?.stopAccessingSecurityScopedResource() }; scopeGranted = false
        monitoredFolder = nil
    }

    private func folderChanged() {
        guard let root = monitoredFolder else { return }
        var directory: ObjCBool = false
        guard root.resolvingSymlinksInPath().path == root.path,
              FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
            stopMonitoring(); message = "Monitoramento interrompido: a pasta foi removida, renomeada ou substituída por um link."; return
        }
        lastObservedChange = Date(); pendingAutomaticScan = true
        scheduleAutomaticScan()
    }

    private func scheduleAutomaticScan() {
        guard monitoring, pendingAutomaticScan else { return }
        rescanTask?.cancel(); rescanTask = nil
        // Preserve the user's current review and wait for an in-flight audit.
        guard !busy, selectedBrowsers.isEmpty else { return }
        let delay = max(2, 15 - Date().timeIntervalSince(lastScanStarted))
        rescanTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled, self.monitoring, self.pendingAutomaticScan,
                  !self.busy, self.selectedBrowsers.isEmpty else { return }
            self.performScan(automatic: true)
        }
    }

    func useDownloads() { changeFolder(nil) }

    private func changeFolder(_ url: URL?) {
        let restart = monitoring
        stopMonitoring(); folder = url
        if restart { startMonitoring() } else { scan() }
    }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Analisar pasta"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeFolder(url)
    }

    func trash() {
        guard !busy, let snapshot, !selectedTraces.isEmpty else { return }
        let selected = Set(selectedTraces.map(\.id))
        busy = true
        task = Task {
            defer { busy = false; if pendingAutomaticScan { scheduleAutomaticScan() } }
            do {
                let outcomes = try await engine.trashTraces(snapshot, selectedIDs: selected)
                let moved = outcomes.filter { $0.destination != nil }.count
                message = "\(moved) arquivo(s) movido(s) para a Lixeira.\n" + outcomes.compactMap { $0.error.map { "\($0)" } }.joined(separator: "\n")
                self.snapshot = nil; selectedBrowsers = []
            } catch { message = error.localizedDescription }
        }
    }
}

struct ProtectionView: View {
    @StateObject private var model = ProtectionViewModel.shared
    @State private var showingConfirmation = false
    @State private var selectedSection = ProtectionSection.security
    @State private var showingCoverage = false

    private enum ProtectionSection: String, CaseIterable {
        case security = "Segurança", privacy = "Privacidade", permissions = "Permissões", monitoring = "Monitoramento"
    }

    var body: some View {
        Group {
            if model.busy && model.snapshot == nil {
                ScanOrbitView(title: "Verificando seu Mac", detail: "Conteúdo local, inicialização, privacidade e ajustes de segurança", progress: nil) { model.cancel() }
            } else if let snapshot = model.snapshot {
                results(snapshot)
            } else {
                VStack(spacing: 12) {
                    ModuleLandingView(title: "Proteção", subtitle: "Revise a segurança e a privacidade do seu Mac. Verificação de conteúdo com ClamAV quando instalado; sem ele, somente teste EICAR.", symbol: "hand.raised.fill", accent: .pink,
                                      features: [("shield.lefthalf.filled", "Verificação local"), ("hand.raised", "Privacidade"), ("lock.shield", "Permissões")]) { model.scan() }
                    folderControls
                    if model.monitoring { monitorCard }
                    statusMessage
                }
            }
        }
        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingConfirmation) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mover rastros para a Lixeira?").font(.system(size: 24, weight: .semibold))
                Text("Feche totalmente os navegadores selecionados. Cookies removidos desconectam sites; o histórico removido deixa de aparecer no navegador. A Lixeira mantém os arquivos até você esvaziá-la.").foregroundStyle(AppStyle.muted)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.selectedTraces) { trace in Text(trace.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                    }
                }.frame(maxHeight: 230)
                HStack { Spacer(); Button("Cancelar") { showingConfirmation = false }; Button("Confirmar e mover") { showingConfirmation = false; model.trash() } }
            }.padding(26).frame(width: 620).background(AppStyle.background).preferredColorScheme(.dark)
        }
    }

    private var folderControls: some View {
        HStack(spacing: 14) {
            Label(model.folder?.lastPathComponent ?? "Downloads", systemImage: "folder")
                .foregroundStyle(AppStyle.muted)
            Button("Escolher pasta…") { model.chooseFolder() }.disabled(model.busy)
            if model.folder != nil { Button("Usar Downloads") { model.useDownloads() }.disabled(model.busy) }
        }.font(.system(size: 12))
    }

    @ViewBuilder private var statusMessage: some View {
        if let message = model.message {
            Text(message).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var monitorCard: some View {
            card("Monitoramento local", icon: "eye") {
                Toggle("Monitorar alterações na pasta", isOn: Binding(get: { model.monitoring }, set: { enabled in
                    if enabled { model.startMonitoring() } else { model.stopMonitoring() }
                })).disabled(model.busy && !model.monitoring)
                Text("Observa a pasta e subpastas enquanto este app está aberto e repete a auditoria local após mudanças, com intervalo mínimo de 15 segundos. A revisão selecionada é preservada até você concluir ou desmarcar os itens. ClamAV é usado somente quando instalado com base local; este monitor não certifica proteção antivírus. Nenhum arquivo é removido automaticamente.")
                    .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                if let root = model.monitoredFolder {
                    Text("Ativo: \(root.path)").font(.system(size: 11, design: .monospaced)).foregroundStyle(AppStyle.mint).textSelection(.enabled)
                    if let date = model.lastObservedChange { Text("Última alteração: \(date.formatted(date: .omitted, time: .standard))").font(.system(size: 11)).foregroundStyle(AppStyle.muted) }
                    if model.pendingAutomaticScan { Text("Nova auditoria aguardando o intervalo, a análise atual ou a conclusão da revisão.").font(.system(size: 11)).foregroundStyle(AppStyle.muted) }
                }
                if let date = model.lastAudit { Text("Última auditoria concluída: \(date.formatted(date: .abbreviated, time: .standard))").font(.system(size: 11)).foregroundStyle(AppStyle.muted) }
            }
    }

    private func results(_ snapshot: ProtectionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Proteção").font(.system(size: 32, weight: .semibold))
                    Text("Verificação local concluída · \(snapshot.scannedFiles) arquivos inspecionados")
                        .foregroundStyle(AppStyle.muted)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Analisar novamente") { model.scan() }.buttonStyle(.bordered).disabled(model.busy)
            }
            folderControls
            Picker("Área de proteção", selection: $selectedSection) {
                ForEach(ProtectionSection.allCases, id: \.self) { section in Text(section.rawValue).tag(section) }
            }.pickerStyle(.segmented)
            statusMessage
            switch selectedSection {
            case .security:
                securityCards(snapshot)
            case .privacy:
                privacyCard(snapshot)
            case .permissions:
                permissionsCard(snapshot)
            case .monitoring:
                monitorCard
            }
            DisclosureGroup("Cobertura da análise · \(snapshot.issues.count) avisos", isExpanded: $showingCoverage) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A análise integrada reconhece o teste EICAR. ClamAV é executado somente quando instalado com assinaturas locais; não há download de dados. Os resultados não certificam ausência de malware.")
                    Text("Pasta: \(snapshot.scanRoot.path) · até 3.000 itens, 8 MB por arquivo e 64 MB lidos. Links simbólicos e pacotes são ignorados.")
                    ForEach(Array(snapshot.issues.enumerated()), id: \.offset) { _, issue in Text(issue) }
                }.font(.system(size: 11)).foregroundStyle(AppStyle.muted).textSelection(.enabled).padding(.top, 8)
            }.font(.system(size: 12)).foregroundStyle(AppStyle.muted)
        }
    }

    private func securityCards(_ snapshot: ProtectionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
                card("Verificação de conteúdo", icon: "doc.text.magnifyingglass") {
                    Text("\(snapshot.scannedFiles) arquivo(s) inspecionado(s) em \(snapshot.scanRoot.path).")
                    Text(snapshot.scannerReport).font(.system(size: 12)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
                    let eicar = snapshot.findings.filter { $0.title == "Arquivo de teste EICAR" }
                    if eicar.isEmpty { Text("Nenhum arquivo de teste EICAR encontrado.").foregroundStyle(AppStyle.muted) }
                    ForEach(eicar) { finding in findingRow(finding) }
                }
                card("Inicialização e persistência", icon: "power") {
                    Text("Plists de LaunchAgents e LaunchDaemons do usuário e de /Library. Heurísticas destacam comandos para revisão; não removemos serviços automaticamente.")
                        .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                    if snapshot.findings.filter({ $0.title != "Arquivo de teste EICAR" }).isEmpty { Text("Nenhum plist legível encontrado neste escopo.").foregroundStyle(AppStyle.muted) }
                    ForEach(snapshot.findings.filter { $0.title != "Arquivo de teste EICAR" }) { finding in findingRow(finding) }
                    Button("Gerenciar Itens de Início") { openSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension") }
                }
        }
    }

    private func privacyCard(_ snapshot: ProtectionSnapshot) -> some View {
                card("Rastros dos navegadores", icon: "hand.raised") {
                    Text("Revise os arquivos exatos abaixo. Selecione um navegador para incluir seus bancos e arquivos auxiliares juntos. Feche o navegador completamente antes de mover; cookies removidos encerram sessões em sites. Histórico e cookies podem voltar se a sincronização do navegador estiver ativa.")
                        .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                    Text("Safari, Chrome, Edge, Brave e cookies do Firefox. O histórico do Firefox compartilha um banco com favoritos e é preservado.")
                        .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                    if snapshot.traces.isEmpty { Text("Nenhum rastro legível encontrado. O macOS pode exigir Acesso Total ao Disco.").foregroundStyle(AppStyle.muted) }
                    ForEach(Array(Set(snapshot.traces.map(\.bundleID))).sorted(), id: \.self) { bundle in
                        let files = snapshot.traces.filter { $0.bundleID == bundle }
                        Toggle(isOn: Binding(get: { model.selectedBrowsers.contains(bundle) }, set: { value in
                            if value { model.selectedBrowsers.insert(bundle) } else { model.selectedBrowsers.remove(bundle) }
                        })) {
                            Text("\(files.first?.browser ?? bundle) · \(ByteText.format(files.reduce(0) { $0 + $1.bytes }))")
                                .font(.system(size: 14, weight: .semibold))
                        }.disabled(model.busy)
                        ForEach(files) { trace in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(trace.kind) · \(ByteText.format(trace.bytes))").font(.system(size: 12))
                                Text(trace.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
                            }.padding(.leading, 22)
                        }
                    }
                    Button("Revisar e mover para a Lixeira") { showingConfirmation = true }.disabled(model.selectedTraces.isEmpty || model.busy)
                }
    }

    private func permissionsCard(_ snapshot: ProtectionSnapshot) -> some View {
                card("Permissões e segurança do macOS", icon: "lock.shield") {
                    ForEach(snapshot.security) { finding in findingRow(finding) }
                    ForEach(snapshot.permissions) { finding in findingRow(finding) }
                    Button("Abrir Privacidade e Segurança") { openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy") }
                    Button("Abrir Firewall") { openSettings("x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall") }
                }
    }

    private func findingRow(_ finding: ProtectionFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(finding.title, systemImage: finding.attention ? "exclamationmark.triangle" : "doc.text")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(finding.attention ? Color.orange : Color.primary)
            Text(finding.detail).font(.system(size: 11)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
            if !finding.path.isEmpty {
                HStack {
                    Text(finding.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
                    Spacer()
                    Button("Mostrar") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: finding.path)]) }
                }
            }
        }.padding(.vertical, 6)
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 19, weight: .semibold))
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func openSettings(_ value: String) {
        if let url = URL(string: value), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
