import AppKit
import SwiftUI

enum AppStyle {
    static let background = Color(red: 0.075, green: 0.025, blue: 0.17)
    static let sidebar = background
    static let mint = Color(red: 0.80, green: 0.80, blue: 1)
    static let aqua = Color(red: 0.58, green: 0.34, blue: 0.95)
    static let muted = Color.secondary
    static let card = Color.primary.opacity(0.06)
}

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case smartCare, analysis, protection, performance, applications, organization, spaceLens, toolbox, activities
        case advanced, largeFiles, trash, photos, slimming, assistant
        var id: String { rawValue }
        static let primary: [Section] = [.smartCare, .analysis, .protection, .performance, .applications, .organization, .spaceLens]
        var title: String {
            switch self {
            case .smartCare: "Cuidados Inteligentes"
            case .analysis: "Limpeza"
            case .protection: "Proteção"
            case .performance: "Desempenho"
            case .applications: "Aplicativos"
            case .organization: "Acúmulos"
            case .spaceLens: "Lupa de Espaço"
            case .toolbox: "Ferramentas"
            case .activities: "Atividades"
            case .advanced: "Dados do sistema"
            case .largeFiles: "Arquivos grandes"
            case .trash: "Lixos"
            case .photos: "Fotos"
            case .slimming: "Otimizar aplicativos"
            case .assistant: "Guia local"
            }
        }
        var icon: String {
            switch self {
            case .smartCare: "desktopcomputer"
            case .analysis: "opticaldisc.fill"
            case .protection: "hand.raised.fill"
            case .performance: "bolt.fill"
            case .applications: "app.badge.fill"
            case .organization: "folder.fill"
            case .spaceLens: "internaldrive.fill"
            case .toolbox: "square.3.layers.3d"
            case .activities: "waveform.path"
            case .advanced: "externaldrive.fill"
            case .largeFiles: "doc.fill"
            case .trash: "trash.fill"
            case .photos: "photo.on.rectangle.angled"
            case .slimming: "arrow.down.right.and.arrow.up.left"
            case .assistant: "questionmark.circle"
            }
        }
        var parent: Section {
            switch self {
            case .advanced, .trash: .analysis
            case .largeFiles, .photos: .organization
            case .slimming, .assistant: .toolbox
            default: self
            }
        }
        var accent: Color {
            switch parent {
            case .analysis: Color(red: 0.39, green: 0.91, blue: 0.39)
            case .protection: Color(red: 1, green: 0.28, blue: 0.64)
            case .performance: Color(red: 1, green: 0.66, blue: 0.15)
            case .applications: Color(red: 0.18, green: 0.72, blue: 1)
            case .organization: Color(red: 0.20, green: 0.87, blue: 0.85)
            case .spaceLens: Color(red: 0.5, green: 0.5, blue: 1)
            default: Color(red: 0.91, green: 0.30, blue: 0.94)
            }
        }
        var gradient: [Color] {
            switch parent {
            case .analysis: [Color(red: 0.02, green: 0.31, blue: 0.11), Color(red: 0.17, green: 0.30, blue: 0.04), Color(red: 0.01, green: 0.14, blue: 0.08)]
            case .protection: [Color(red: 0.32, green: 0.02, blue: 0.16), Color(red: 0.40, green: 0.02, blue: 0.34), Color(red: 0.22, green: 0.01, blue: 0.18)]
            case .performance: [Color(red: 0.45, green: 0.13, blue: 0.01), Color(red: 0.39, green: 0.07, blue: 0.015), Color(red: 0.25, green: 0.04, blue: 0.01)]
            case .applications: [Color(red: 0.02, green: 0.16, blue: 0.36), Color(red: 0.10, green: 0.12, blue: 0.42), Color(red: 0.08, green: 0.10, blue: 0.29)]
            case .organization: [Color(red: 0.01, green: 0.30, blue: 0.34), Color(red: 0.01, green: 0.34, blue: 0.29), Color(red: 0.01, green: 0.18, blue: 0.18)]
            case .spaceLens: [Color(red: 0.15, green: 0.12, blue: 0.38), Color(red: 0.19, green: 0.14, blue: 0.44), Color(red: 0.07, green: 0.06, blue: 0.22)]
            default: [Color(red: 0.19, green: 0.025, blue: 0.33), Color(red: 0.30, green: 0.045, blue: 0.49), Color(red: 0.065, green: 0.025, blue: 0.24)]
            }
        }
    }
    @StateObject private var smartCareModel = SmartCareViewModel()
    @StateObject private var model = AnalysisViewModel()
    @StateObject private var advancedModel = AdvancedCleanupViewModel()
    @StateObject private var applicationsModel = ApplicationsViewModel()
    @StateObject private var largeFilesModel = LargeFilesViewModel()
    @StateObject private var organizationModel = OrganizationViewModel()
    @StateObject private var spaceLensModel = SpaceLensViewModel()
    @StateObject private var activities = ActivityStore()
    @State private var section: Section = .smartCare
    @State private var showingSettings = false
    @State private var showingExclusions = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar
                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        module
                            .frame(maxWidth: 1080)
                            .frame(minHeight: max(570, geometry.size.height - 100), alignment: .top)
                            .padding(.horizontal, 32).padding(.bottom, 20)
                            .frame(maxWidth: .infinity)
                    }.scrollIndicators(.hidden)
                }
            }
            .background {
                ZStack {
                    LinearGradient(colors: section.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Ellipse().fill(section.accent.opacity(0.17)).frame(width: 650, height: 550).blur(radius: 100).offset(x: 180, y: 130)
                }.ignoresSafeArea()
            }
        }
        .frame(minWidth: 1060, minHeight: 720)
        .preferredColorScheme(.dark).tint(section.accent)
        .sheet(isPresented: $showingSettings) { AppSettingsView() }
        .sheet(isPresented: $showingExclusions) { ExclusionsSheet(model: model) }
        .onAppear { model.loadExclusions() }
        .onReceive(NotificationCenter.default.publisher(for: .cleanMacNavigate)) { event in
            if event.object as? String == "settings" { showingSettings = true }
            else if let raw = event.object as? String, let target = Section(rawValue: raw) { navigate(target) }
        }
        .onChange(of: smartCareModel.state) { _, state in
            if state == .results { activities.record("Cuidados Inteligentes", detail: "Análise concluída. Resultados prontos para revisão.", symbol: "desktopcomputer") }
        }
        .onChange(of: model.state) { _, state in
            if state == .completed { activities.record("Limpeza", detail: "Operação de limpeza concluída. Consulte o resultado para ver os itens processados.", symbol: "opticaldisc.fill") }
        }
        .onChange(of: applicationsModel.state) { _, state in
            if state == .results { activities.record("Aplicativos", detail: "Inventário local atualizado.", symbol: "app.badge.fill") }
        }
        .onChange(of: organizationModel.state) { _, state in
            if state == .results { activities.record("Acúmulos", detail: "Análise dos arquivos pessoais concluída.", symbol: "folder.fill") }
        }
        .onChange(of: spaceLensModel.state) { _, state in
            if state == .results { activities.record("Lupa de Espaço", detail: "Mapa de armazenamento atualizado.", symbol: "internaldrive.fill") }
        }
    }

    private var compactSidebar: Bool {
        switch section {
        case .smartCare: smartCareModel.state == .results
        case .analysis: model.state != .initial && model.state != .scanning
        case .applications: applicationsModel.state == .results
        case .organization: organizationModel.state == .results
        case .spaceLens: spaceLensModel.state == .results
        case .advanced, .largeFiles, .trash, .photos, .slimming: true
        default: false
        }
    }

    private var sidebar: some View {
        VStack(spacing: 6) {
            Color.clear.frame(height: 92)
            ForEach(Section.primary) { navigationRow($0) }
            Spacer(minLength: 50)
            navigationRow(.toolbox)
            navigationRow(.activities)
            HStack {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }.help("Ajustes")
                Spacer()
                if !compactSidebar { Text("Clean Mac").font(.system(size: 11, weight: .medium)) }
            }.foregroundStyle(.white.opacity(0.4)).buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 16)
        }.padding(.horizontal, 12).padding(.bottom, 22).frame(width: compactSidebar ? 72 : 225)
            .background(.black.opacity(0.12))
            .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1).padding(.vertical, 100) }
    }

    private func navigationRow(_ item: Section) -> some View {
        Button { navigate(item) } label: {
            HStack(spacing: 12) {
                ModuleIcon(symbol: item.icon, accent: section.parent == item ? section.accent : .white.opacity(0.35), size: 22)
                if !compactSidebar { Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85); Spacer(minLength: 0) }
            }.padding(.horizontal, 14).frame(height: 45).contentShape(Rectangle())
                .background(section.parent == item ? .white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(section.parent == item ? 0.09 : 0), lineWidth: 1))
        }.buttonStyle(.plain).foregroundStyle(.white.opacity(section.parent == item ? 1 : 0.85))
            .help(item.title).accessibilityLabel(item.title)
            .accessibilityIdentifier("navigation." + item.rawValue)
            .accessibilityAddTraits(section.parent == item ? .isSelected : [])
    }

    private var topBar: some View {
        HStack {
            if section.parent != section {
                Button { navigate(section.parent) } label: { Label(section.parent.title, systemImage: "chevron.left") }
            }
            Spacer()
            if ScanScope.isFixture { Text("Pasta de teste").foregroundStyle(.yellow) }
            Button { showingExclusions = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.help("Exclusões de limpeza")
            Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("Ajustes")
        }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 28).frame(height: 60)
    }

    private func navigate(_ target: Section) {
        section = target
        if target == .trash { model.scanTrash() }
    }

    @ViewBuilder private var module: some View {
        switch section {
        case .smartCare:
            SmartCareView(model: smartCareModel,
                openCleanup: { if let result = smartCareModel.snapshot { model.accept(result.cleanupResult); advancedModel.accept(result.advancedResult) }; navigate(.analysis) },
                openAdvanced: { if let result = smartCareModel.snapshot { advancedModel.accept(result.advancedResult) }; navigate(.advanced) },
                openOrganization: { if let result = smartCareModel.snapshot { organizationModel.accept(result.organizationResult) }; navigate(.organization) },
                openLargeFiles: { if let result = smartCareModel.snapshot { largeFilesModel.accept(result.largeFilesResult) }; navigate(.largeFiles) },
                openApplications: { if let result = smartCareModel.snapshot { applicationsModel.accept(result.applicationsResult) }; navigate(.applications) },
                openPerformance: { navigate(.performance) },
                openProtection: {
                    let protection = ProtectionViewModel.shared
                    if !protection.busy, protection.selectedBrowsers.isEmpty, let result = smartCareModel.snapshot?.protectionResult { protection.snapshot = result }
                    navigate(.protection)
                })
        case .analysis: CleanupModuleView(model: model, advancedModel: advancedModel)
        case .protection: ProtectionView()
        case .performance: PerformanceView()
        case .applications: ApplicationsView(model: applicationsModel)
        case .organization: OrganizationView(model: organizationModel, openLargeFiles: { navigate(.largeFiles) }, openPhotos: { navigate(.photos) })
        case .spaceLens: SpaceLensView(model: spaceLensModel)
        case .toolbox: tools
        case .activities: ActivityHistoryView(store: activities)
        case .advanced: AdvancedCleanupView(model: advancedModel)
        case .largeFiles: LargeFilesView(model: largeFilesModel)
        case .trash: TrashView(model: model)
        case .photos: PhotosClutterView()
        case .slimming: AppSlimmingView()
        case .assistant: LocalAssistantView { navigate($0) }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Ferramentas").font(.system(size: 34, weight: .regular))
            Text("Mais formas de cuidar do seu Mac.").foregroundStyle(AppStyle.muted)
            HStack(spacing: 14) {
                toolShortcut(.slimming, detail: "Idiomas e arquiteturas")
                toolShortcut(.photos, detail: "Duplicatas e imagens similares")
                toolShortcut(.assistant, detail: "Encontre a ferramenta certa")
            }
            ToolboxView()
        }.padding(.top, 20)
    }
    private func toolShortcut(_ target: Section, detail: String) -> some View {
        Button { navigate(target) } label: {
            VStack(alignment: .leading, spacing: 12) {
                ModuleIcon(symbol: target.icon, accent: section.accent, size: 38)
                Text(target.title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
            }.frame(maxWidth: .infinity, minHeight: 115, alignment: .leading)
                .padding(18).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

#Preview { ContentView() }
