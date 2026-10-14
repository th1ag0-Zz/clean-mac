import AppKit
import ServiceManagement
import SwiftUI

struct PerformanceView: View {
    @StateObject private var health = SystemHealth()
    @State private var showingReview = false
    @State private var category: Category = .maintenance
    private enum Category: String, CaseIterable {
        case maintenance = "Manutenção", startup = "Itens de início", apps = "Apps em execução"
    }
    @State private var startupEntries: [StartupEntry] = []
    @State private var runningApps: [NSRunningApplication] = []
    @State private var memoryByPID: [Int32: UInt64] = [:]
    @State private var readingMemory = false
    @State private var refreshID = UUID()
    @State private var appToQuit: NSRunningApplication?
    @State private var showingQuitConfirmation = false
    @State private var showingReindexConfirmation = false
    @State private var showingDNSConfirmation = false
    @State private var reindexing = false
    @State private var flushingDNS = false
    @State private var message: String?

    var body: some View {
        Group {
            if !showingReview {
                ModuleLandingView(title: "Desempenho", subtitle: "Ajude seu Mac a trabalhar melhor.\nRevise a manutenção, os itens de início e os apps em execução.", symbol: "bolt.fill", accent: .orange,
                                  features: [("wrench.and.screwdriver", "Tarefas de manutenção"), ("power", "Itens de início"), ("app.badge", "Apps em execução")]) {
                    refreshApps()
                    refreshStartup()
                    showingReview = true
                }
            } else {
                review
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { health.start(); if showingReview { refreshApps(); refreshStartup() } }
        .onDisappear { health.stop(); refreshID = UUID() }
        .confirmationDialog("Encerrar \(appToQuit?.localizedName ?? "app")?", isPresented: $showingQuitConfirmation) {
            Button("Encerrar app") {
                guard canQuitApps, let appToQuit else { return }
                message = appToQuit.terminate()
                    ? "Pedido de encerramento enviado para \(appToQuit.localizedName ?? "o app")."
                    : "Não foi possível encerrar \(appToQuit.localizedName ?? "o app")."
                refreshApps()
            }
        } message: {
            Text("Salve alterações nesse app antes de continuar. Ele poderá pedir confirmação para fechar.")
        }
        .confirmationDialog("Reconstruir o índice do Spotlight?", isPresented: $showingReindexConfirmation) {
            Button("Solicitar reindexação") { reindexSpotlight() }
        } message: {
            Text("A busca pode mostrar resultados incompletos enquanto o macOS reconstrói o índice.")
        }
        .confirmationDialog("Esvaziar o cache DNS local?", isPresented: $showingDNSConfirmation) {
            Button("Esvaziar cache DNS") { flushDNS() }
        } message: {
            Text("O macOS fará novas consultas para os nomes que saírem do cache.")
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Desempenho").font(.system(size: 30, weight: .bold))
                Spacer()
                Button("Atualizar", systemImage: "arrow.clockwise") { refreshApps(); refreshStartup() }
                    .foregroundStyle(AppStyle.muted)
            }
            HStack(spacing: 12) {
                SummaryCard(title: "CPU", value: health.snapshot.cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "Lendo…", note: "Uso total · atualização a cada 2 s", icon: "cpu")
                SummaryCard(title: "Memória em uso", value: ByteText.format(health.snapshot.memoryUsed), note: "De \(ByteText.format(health.snapshot.memoryTotal)) · estimativa física", icon: "memorychip")
                SummaryCard(title: "Espaço disponível", value: ByteText.format(health.snapshot.diskAvailable), note: "Volume da sua pasta pessoal", icon: "internaldrive")
            }
            HStack(spacing: 22) {
                Label("Ligado há \(uptimeText)", systemImage: "clock")
                Label("Estado térmico: \(health.snapshot.thermalState)", systemImage: "thermometer.medium")
                if let battery = health.snapshot.batteryPercent {
                    Label("\(battery)%" + (health.snapshot.batteryCharging ? " · carregando" : ""), systemImage: "battery.100percent")
                }
            }.font(.system(size: 12)).foregroundStyle(AppStyle.muted)

            Picker("Categoria", selection: $category) {
                ForEach(Category.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if let message {
                Text(message).font(.system(size: 12)).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch category {
                    case .maintenance: maintenanceTasks
                    case .startup: startupItems
                    case .apps: appList
                    }
                }
            }.frame(minHeight: 290, maxHeight: 410)
        }
    }

    private var maintenanceTasks: some View {
        VStack(alignment: .leading, spacing: 14) {
            card(title: "Reindexar Spotlight", icon: "magnifyingglass") {
                Text("Reconstrua o índice de busca do disco de inicialização. A pesquisa pode ficar incompleta até terminar. O macOS pode solicitar autorização.")
                    .foregroundStyle(AppStyle.muted)
                HStack {
                    Button("Solicitar reindexação") { showingReindexConfirmation = true }
                        .disabled(reindexing || !canReindex)
                    if reindexing { ProgressView().tint(AppStyle.mint) }
                }
                Text("Você também pode gerenciar as exclusões de busca nos Ajustes do Spotlight.")
                    .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                Button("Abrir Ajustes do Spotlight") { openSystemSettings() }
            }

            card(title: "Esvaziar cache DNS", icon: "network") {
                Text("Solicita ao macOS que descarte respostas DNS locais em cache. Útil quando um endereço mudou e o Mac ainda usa o antigo.")
                    .foregroundStyle(AppStyle.muted)
                HStack {
                    Button("Esvaziar cache") { showingDNSConfirmation = true }
                        .disabled(flushingDNS || !canReindex)
                    if flushingDNS { ProgressView().tint(AppStyle.mint) }
                }
            }

        }
    }

    private var startupItems: some View {
        VStack(alignment: .leading, spacing: 14) {
            card(title: "Gerenciar inicialização", icon: "power") {
                Text("Revise os serviços de inicialização e gerencie os apps de início nos Ajustes do macOS.")
                    .foregroundStyle(AppStyle.muted)
                Button("Abrir Itens de Início") { openLoginItems() }
                Text("Agentes e serviços instalados por apps. A presença de um plist não significa que o serviço esteja em execução. Os itens gerenciados pelo macOS aparecem nos Ajustes.")
                    .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                if startupEntries.isEmpty { Text("Nenhum agente de terceiros legível encontrado.").foregroundStyle(AppStyle.muted) }
                ForEach(startupEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.label).font(.system(size: 13, weight: .medium))
                            Text("\(entry.scope) · \(entry.startsAtLoad ? "RunAtLoad ativo" : "início sob demanda")").font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                            Text(entry.program).font(.system(size: 10, design: .monospaced)).foregroundStyle(AppStyle.muted).lineLimit(1).help(entry.program)
                        }
                        Spacer()
                        Button("Mostrar plist") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                    }.padding(.vertical, 4)
                }
            }

            card(title: "Processos em segundo plano", icon: "gearshape.2") {
                Text("Veja quais apps podem trabalhar em segundo plano em Itens de Início e Extensões. Para examinar processos em execução e uso de memória, abra o Monitor de Atividade.")
                    .foregroundStyle(AppStyle.muted)
                HStack(spacing: 18) {
                    Button("Abrir Itens de Início") { openLoginItems() }
                    Button("Abrir Monitor de Atividade") { openActivityMonitor() }
                }
            }
        }
    }

    private var appList: some View {
            card(title: "Apps em execução", icon: "app.badge") {
                Text("Encerre apps que não está usando para liberar memória. Salve seu trabalho antes.")
                    .foregroundStyle(AppStyle.muted)
                Text("RAM do processo principal; processos auxiliares não estão incluídos.")
                    .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                HStack {
                    Text("Apps em execução").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button("Atualizar lista") { refreshApps() }.foregroundStyle(AppStyle.mint)
                }
                if runningApps.isEmpty {
                    Text("Nenhum outro app com interface encontrado.").foregroundStyle(AppStyle.muted)
                } else {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                            }
                            Text(app.localizedName ?? "App sem nome")
                            Spacer()
                            Text(memoryLabel(for: app.processIdentifier))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AppStyle.muted)
                                .frame(minWidth: 125, alignment: .trailing)
                            Button("Encerrar") {
                                appToQuit = app
                                showingQuitConfirmation = true
                            }
                            .disabled(!canQuitApps)
                        }
                        .font(.system(size: 13))
                        .padding(.vertical, 5)
                    }
                }
            }

    }

    private func card<Content: View>(title: String, icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.system(size: 19, weight: .semibold))
            content()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var canQuitApps: Bool { !LocalCommand.isFixture }
    private var canReindex: Bool { !LocalCommand.isFixture }
    private var uptimeText: String {
        let hours = Int(health.snapshot.uptime) / 3600
        return hours >= 24 ? "\(hours / 24) d \(hours % 24) h" : "\(hours) h \(Int(health.snapshot.uptime) / 60 % 60) min"
    }

    private func refreshStartup() {
        Task { startupEntries = await Task.detached(priority: .utility) { StartupEntry.inventory() }.value }
    }

    private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.activationPolicy == .regular &&
                      $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        let currentID = UUID()
        refreshID = currentID
        readingMemory = true
        memoryByPID = [:]
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                ProcessMemoryReader.snapshot()
            }.value
            guard refreshID == currentID else { return }
            memoryByPID = snapshot ?? [:]
            readingMemory = false
        }
    }

    private func memoryLabel(for pid: Int32) -> String {
        if readingMemory { return "Lendo RAM…" }
        guard let bytes = memoryByPID[pid] else { return "RAM indisponível" }
        return ByteText.format(bytes)
    }

    private func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func openSystemSettings() {
        let app = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if !NSWorkspace.shared.open(app) { message = "Não foi possível abrir Ajustes do Sistema." }
    }

    private func openActivityMonitor() {
        let app = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        if !NSWorkspace.shared.open(app) { message = "Não foi possível abrir o Monitor de Atividade." }
    }

    private func reindexSpotlight() {
        guard canReindex else { return }
        reindexing = true
        message = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { LocalCommand.maintenance(.spotlight) }.value
            reindexing = false
            message = result.status == 0
                ? "Solicitação enviada ao Spotlight. A reconstrução continua em segundo plano. \(result.output)"
                : "A reindexação não foi concluída: \(result.output)"
        }
    }

    private func flushDNS() {
        guard canReindex else { return }
        flushingDNS = true
        message = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { LocalCommand.maintenance(.dns) }.value
            flushingDNS = false
            message = result.status == 0
                ? "Cache DNS descartado e mDNSResponder notificado pelo macOS."
                : "O cache DNS não foi esvaziado: \(result.output)"
        }
    }
}
