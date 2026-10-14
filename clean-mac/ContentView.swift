import AppKit
import SwiftUI

enum AppStyle {
    static let background = Color(red: 0.105, green: 0.025, blue: 0.24)
    static let sidebar = Color(red: 0.10, green: 0.025, blue: 0.24)
    static let mint = Color(red: 0.98, green: 0.53, blue: 0.86)
    static let aqua = Color(red: 0.65, green: 0.28, blue: 0.96)
    static let muted = Color(red: 0.82, green: 0.74, blue: 0.90)
    static let card = Color.white.opacity(0.09)
}

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case smartCare, analysis, protection, performance, applications, organization, spaceLens, advanced, largeFiles, trash, photos, slimming, toolbox, assistant
        var id: String { rawValue }
        var title: String {
            switch self {
            case .smartCare: "Cuidados Inteligentes"
            case .analysis: "Limpeza"
            case .protection: "Proteção"
            case .performance: "Desempenho"
            case .applications: "Aplicativos"
            case .organization: "Acúmulos"
            case .spaceLens: "Lupa de Espaço"
            case .advanced: "Limpeza adicional"
            case .largeFiles: "Arquivos grandes"
            case .trash: "Lixeiras"
            case .photos: "Fotos locais"
            case .slimming: "Otimizar aplicativos"
            case .toolbox: "Ferramentas"
            case .assistant: "Assistente local"
            }
        }
        var icon: String {
            switch self {
            case .smartCare: "sparkles"
            case .analysis: "sparkle.magnifyingglass"
            case .protection: "shield.lefthalf.filled"
            case .performance: "speedometer"
            case .applications: "square.grid.2x2.fill"
            case .organization: "square.stack.3d.up.fill"
            case .spaceLens: "chart.pie.fill"
            case .advanced: "slider.horizontal.3"
            case .largeFiles: "doc.zipper"
            case .trash: "trash.fill"
            case .photos: "photo.on.rectangle.angled"
            case .slimming: "arrow.down.right.and.arrow.up.left"
            case .toolbox: "wrench.and.screwdriver.fill"
            case .assistant: "bubble.left.and.text.bubble.right.fill"
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
    @State private var section: Section = .smartCare
    @StateObject private var health = SystemHealth()
    @State private var showingSettings = false
    @State private var showingExclusions = false
    @State private var showingConfirmation = false
    @State private var expandedCategories = Set(AnalysisCategory.allCases)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            mainArea
        }
        .frame(minWidth: 1060, minHeight: 740)
        .background(AppStyle.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingExclusions) { ExclusionsSheet(model: model) }
        .sheet(isPresented: $showingConfirmation) { ConfirmationSheet(model: model) }
        .sheet(isPresented: $showingSettings) { AppSettingsView() }
        .onAppear { model.loadExclusions(); health.start() }
        .onDisappear { health.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .cleanMacNavigate)) { event in
            if event.object as? String == "settings" { showingSettings = true }
            else if let raw = event.object as? String, let destination = Section(rawValue: raw) { navigate(destination) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [AppStyle.mint, AppStyle.aqua], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 22)).foregroundStyle(.white)
                }.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean Mac").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Um Mac mais leve.").font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                }
            }.padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 30)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(Section.allCases.prefix(7))) { item in navigationRow(item) }
                    Text("MAIS FERRAMENTAS").font(.system(size: 9, weight: .bold)).tracking(1.5)
                        .foregroundStyle(AppStyle.muted.opacity(0.65)).padding(.horizontal, 13).padding(.top, 24).padding(.bottom, 6)
                    ForEach(Array(Section.allCases.dropFirst(7))) { item in navigationRow(item) }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "internaldrive").foregroundStyle(AppStyle.mint)
                    Text("Armazenamento").font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                ProgressView(value: diskFraction).tint(AppStyle.mint)
                Text(health.snapshot.diskTotal > 0 ? "\(ByteText.format(health.snapshot.diskAvailable)) disponíveis de \(ByteText.format(health.snapshot.diskTotal))" : "Lendo armazenamento…")
                    .font(.system(size: 10)).foregroundStyle(AppStyle.muted)
            }.padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button { showingSettings = true } label: { Label("Ajustes", systemImage: "gearshape") }
                Spacer()
                Button { showingExclusions = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.help("Exclusões de limpeza")
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(AppStyle.muted).padding(14)
            Label(ScanScope.isFixture ? "Pasta de teste" : "Tudo acontece neste Mac", systemImage: "lock.fill")
                .font(.system(size: 10)).foregroundStyle(AppStyle.muted.opacity(0.6)).padding(.horizontal, 12).padding(.bottom, 6)
        }
        .padding(14).frame(width: 242).frame(maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [AppStyle.sidebar, Color(red: 0.08, green: 0.015, blue: 0.21)], startPoint: .top, endPoint: .bottom))
    }

    private var diskFraction: Double {
        let total = health.snapshot.diskTotal
        return total > 0 ? Double(total - min(total, health.snapshot.diskAvailable)) / Double(total) : 0
    }

    private func navigate(_ destination: Section) {
        section = destination
        if destination == .trash { model.scanTrash() }
    }

    private func navigationRow(_ item: Section) -> some View {
        Button { navigate(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon).font(.system(size: 16)).frame(width: 22)
                    .foregroundStyle(section == item ? AppStyle.mint : AppStyle.muted)
                Text(item.title).font(.system(size: 12, weight: section == item ? .semibold : .medium))
                Spacer(minLength: 0)
                if item == .smartCare { Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(AppStyle.mint) }
            }
            .padding(.horizontal, 12).frame(height: 39).contentShape(Rectangle())
            .background(section == item ? .white.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) { if section == item { Capsule().fill(AppStyle.mint).frame(width: 3, height: 19) } }
        }
        .buttonStyle(.plain).foregroundStyle(section == item ? .white : AppStyle.muted)
        .accessibilityAddTraits(section == item ? .isSelected : [])
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("navigation." + item.rawValue)
    }

    private var mainArea: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.055, blue: 0.54),
                                    Color(red: 0.22, green: 0.035, blue: 0.46),
                                    AppStyle.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.77, green: 0.12, blue: 0.87).opacity(0.38))
                .frame(width: 600, height: 600).blur(radius: 110).offset(x: -150, y: 180)
            Circle().fill(AppStyle.aqua.opacity(0.17))
                .frame(width: 500, height: 500).blur(radius: 110).offset(x: 300, y: -240)
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        Label("MEU MAC", systemImage: "laptopcomputer").font(.system(size: 10, weight: .bold)).tracking(2)
                        Spacer()
                        Text(section.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    }.foregroundStyle(AppStyle.muted.opacity(0.8))
                    if section == .smartCare {
                        SmartCareView(model: smartCareModel,
                                      openCleanup: { if let result = smartCareModel.snapshot { model.accept(result.cleanupResult) }; section = .analysis },
                                      openAdvanced: { if let result = smartCareModel.snapshot { advancedModel.accept(result.advancedResult) }; section = .advanced },
                                      openOrganization: { if let result = smartCareModel.snapshot { organizationModel.accept(result.organizationResult) }; section = .organization },
                                      openLargeFiles: { if let result = smartCareModel.snapshot { largeFilesModel.accept(result.largeFilesResult) }; section = .largeFiles },
                                      openApplications: { if let result = smartCareModel.snapshot { applicationsModel.accept(result.applicationsResult) }; section = .applications },
                                      openPerformance: { section = .performance })
                    } else if section == .protection {
                        ProtectionView()
                    } else if section == .photos {
                        PhotosClutterView()
                    } else if section == .slimming {
                        AppSlimmingView()
                    } else if section == .toolbox {
                        ToolboxView()
                    } else if section == .assistant {
                        LocalAssistantView { navigate($0) }
                    } else if section == .trash {
                        TrashView(model: model)
                    } else if section == .advanced {
                        AdvancedCleanupView(model: advancedModel)
                    } else if section == .performance {
                        PerformanceView()
                    } else if section == .applications {
                        ApplicationsView(model: applicationsModel)
                    } else if section == .largeFiles {
                        LargeFilesView(model: largeFilesModel)
                    } else if section == .organization {
                        OrganizationView(model: organizationModel)
                    } else if section == .spaceLens {
                        SpaceLensView(model: spaceLensModel)
                    } else {
                        switch model.state {
                        case .initial: initialContent
                        case .scanning: scanningContent
                        case .empty: emptyContent
                        case .results: resultsContent
                        case .cleaning: cleaningContent
                        case .completed: completedContent
                        case .failed: failedContent
                        }
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(.horizontal, 42).padding(.top, 34).padding(.bottom, 50)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var initialContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            ViewThatFits(in: .horizontal) {
                hero(artSize: 270, titleSize: 43)
                hero(artSize: 190, titleSize: 34)
            }
            HStack(spacing: 14) {
                feature("eye", "Veja antes", "Cada item tem caminho, tamanho e motivo.")
                feature("checklist", "Você escolhe", "Nada vem selecionado por padrão.")
                feature("lock.shield", "No seu Mac", "A análise acontece localmente.")
            }
        }
    }

    private func hero(artSize: CGFloat, titleSize: CGFloat) -> some View {
        HStack(spacing: 44) {
            CleanerArtwork()
                .frame(width: artSize, height: artSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 20) {
                Text("Cuide do espaço.\nFique com o que importa.")
                    .font(.system(size: titleSize, weight: .medium, design: .rounded))
                    .tracking(-1.2).fixedSize(horizontal: false, vertical: true)
                Text("Encontre caches, relatórios de falha, logs e instaladores antigos. Revise cada sugestão antes de decidir o que fazer.")
                    .font(.system(size: 15)).foregroundStyle(AppStyle.muted)
                    .lineSpacing(4)
                HStack(spacing: 10) {
                    Label("Análise local", systemImage: "magnifyingglass")
                    Label("Revisão antes da limpeza", systemImage: "checkmark.shield")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                ActionButton(title: "Analisar agora", icon: "sparkle.magnifyingglass") {
                    model.startAnalysis()
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: 470, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 440, alignment: .center)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(AppStyle.mint)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(AppStyle.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(18).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var scanningContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Olhando com cuidado")
                .font(.system(size: 42, weight: .semibold, design: .rounded))
            Text("A análise é somente leitura. Você poderá revisar tudo antes de qualquer limpeza.")
                .foregroundStyle(AppStyle.muted)
            VStack(alignment: .leading, spacing: 22) {
                ProgressView().progressViewStyle(.linear).tint(AppStyle.mint)
                Label(model.progress?.category.title ?? "Preparando análise", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                HStack(spacing: 24) {
                    metric("Itens verificados", "\(model.progress?.scannedEntries ?? 0)")
                    metric("Encontrados", "\(model.progress?.foundItems ?? 0)")
                    metric("Tamanho lógico", ByteText.format(model.progress?.foundLogicalBytes ?? 0))
                }
                Button("Cancelar análise") { model.cancelAnalysis() }
                    .buttonStyle(.plain).foregroundStyle(AppStyle.mint)
            }
            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.top, 70)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(title).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "checkmark.circle").font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(AppStyle.mint)
            Text("Nada para revisar agora")
                .font(.system(size: 39, weight: .semibold, design: .rounded))
            Text("Nenhum cache, relatório de falha, log ou instalador corresponde às regras de 30 dias ou mais.")
                .foregroundStyle(AppStyle.muted).frame(maxWidth: 550, alignment: .leading)
            if let result = model.result { issueList(result.issues) }
            ActionButton(title: "Analisar novamente", icon: "arrow.clockwise") { model.startAnalysis() }
        }
        .padding(.top, 65)
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Não foi possível concluir")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
            Text(model.errorMessage ?? "Tente novamente.")
                .foregroundStyle(AppStyle.muted).textSelection(.enabled)

            ActionButton(title: "Tentar novamente", icon: "arrow.clockwise") { model.startAnalysis() }
        }
        .padding(.top, 65)
    }

    private var cleaningContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "arrow.up.doc").font(.system(size: 48)).foregroundStyle(AppStyle.mint)
            Text("Movendo para a Lixeira")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
            Text("Cada item é conferido novamente antes de ser movido.")
                .foregroundStyle(AppStyle.muted)
            if let progress = model.cleanupProgress {
                ProgressView(value: Double(progress.processed), total: Double(progress.total))
                    .tint(AppStyle.mint)
                Text("\(progress.processed) de \(progress.total) · \(progress.currentPath)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppStyle.muted)
            } else {
                ProgressView().tint(AppStyle.mint)
            }
        }
        .padding(.top, 65)
    }

    private var completedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.seal").font(.system(size: 48)).foregroundStyle(AppStyle.mint)
            Text("Limpeza finalizada")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
            if let report = model.cleanupReport {
                Text("\(report.movedCount) itens movidos · \(report.failedCount) falhas")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(ByteText.format(report.movedLogicalBytes)) de tamanho lógico movido para a Lixeira. Espaço efetivamente liberado: ainda não mensurável.")
                    .foregroundStyle(AppStyle.muted)
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(report.outcomes) { outcome in
                        HStack(alignment: .top) {
                            Image(systemName: outcome.moved ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(outcome.moved ? AppStyle.mint : .orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(outcome.candidate.relativePath)
                                    .font(.system(size: 12, design: .monospaced))
                                Text(outcome.moved ? "Movido para a Lixeira" : (outcome.error ?? "Falha"))
                                    .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                            }
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
            }
            ActionButton(title: "Nova análise", icon: "arrow.clockwise") { model.startAnalysis() }
        }
        .padding(.top, 45)
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sua análise").font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text("Revise as sugestões e selecione apenas o que deseja mover para a Lixeira.")
                        .font(.system(size: 14)).foregroundStyle(AppStyle.muted)
                }
                Spacer()
                Button { model.startAnalysis() } label: {
                    Label("Analisar novamente", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain).foregroundStyle(AppStyle.mint).padding(.top, 10)
            }
            if let result = model.result {
                HStack(spacing: 14) {
                    SummaryCard(title: "Encontrado", value: ByteText.format(result.foundBytes),
                                note: "\(result.candidates.count) itens · tamanho lógico", icon: "magnifyingglass")
                    SummaryCard(title: "Selecionado para limpeza", value: ByteText.format(model.selectedBytes),
                                note: "\(model.selectedCandidates.count) itens · estimativa", icon: "checkmark.circle")
                    SummaryCard(title: "Categorias", value: "\(result.groups.count)",
                                note: "tipos encontrados", icon: "square.grid.2x2")
                }
                Text("O tamanho encontrado não é uma promessa de espaço recuperável. Mover itens para a Lixeira ainda não libera esses bytes.")
                    .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                issueList(result.issues)
                HStack {
                    Text("REVISAR ITENS").font(.system(size: 11, weight: .bold)).tracking(1.8)
                    Spacer()
                    Text("Nada selecionado automaticamente").font(.system(size: 11))
                }
                .foregroundStyle(AppStyle.muted).padding(.top, 12)
                ForEach(result.groups, id: \.category) { group in groupCard(group) }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(model.selectedCandidates.count) itens selecionados")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(ByteText.format(model.selectedBytes)) estimados para mover à Lixeira")
                            .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                    }
                    Spacer()
                    ActionButton(title: "Revisar operação", icon: "arrow.right") {
                        showingConfirmation = true
                    }
                    .disabled(model.selectedCandidates.isEmpty)
                }
                .padding(20).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    @ViewBuilder
    private func issueList(_ issues: [AnalysisIssue]) -> some View {
        if !issues.isEmpty {
            DisclosureGroup {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top) {
                            Text(issue.relativePath).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Text(issue.kind.displayName).font(.system(size: 11))
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Análise parcial: \(issues.count) áreas ou itens não verificados",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .tint(.orange).padding(16)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func groupCard(_ group: AnalysisGroup) -> some View {
        let groupPaths = Set(group.candidates.map(\.relativePath))
        let selectedCount = groupPaths.intersection(model.selectedPaths).count
        return DisclosureGroup(isExpanded: Binding(
            get: { expandedCategories.contains(group.category) },
            set: { if $0 { expandedCategories.insert(group.category) }
                   else { expandedCategories.remove(group.category) } }
        )) {
            LazyVStack(spacing: 0) {
                ForEach(group.candidates) { candidate in
                    Divider().overlay(.white.opacity(0.08))
                    candidateRow(candidate)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: group.category == .oldLogs ? "doc.text" : "externaldrive")
                    .font(.system(size: 18)).foregroundStyle(AppStyle.mint).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.category.title).font(.system(size: 16, weight: .semibold))
                    Text("\(selectedCount) de \(group.candidates.count) selecionados · \(ByteText.format(group.logicalBytes))")
                        .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                }
                Spacer()
                Toggle(isOn: Binding(
                    get: { selectedCount == group.candidates.count },
                    set: { model.setSelected($0, for: group) }
                )) { Text("Selecionar grupo").font(.system(size: 11)) }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Selecionar todos os itens de \(group.category.title)")
            }
        }
        .tint(AppStyle.mint).padding(20)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func candidateRow(_ candidate: AnalysisCandidate) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle(isOn: Binding(
                get: { model.selectedPaths.contains(candidate.relativePath) },
                set: { model.setSelected($0, for: candidate) }
            )) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel("Selecionar \(candidate.url.lastPathComponent)")
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.url.lastPathComponent).font(.system(size: 13, weight: .semibold))
                Text(candidate.url.path).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppStyle.muted).lineLimit(2).textSelection(.enabled)
                Text(candidate.reason).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                Text("Modificado em \(candidate.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 10)).foregroundStyle(AppStyle.muted.opacity(0.8))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteText.format(candidate.logicalBytes))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                HStack(spacing: 12) {
                    Button("Finder") { model.showInFinder(candidate) }.help("Mostrar no Finder")
                    Button("Ignorar") { model.exclude(candidate) }
                        .help("Excluir das próximas análises")
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain).foregroundStyle(AppStyle.mint)
            }
        }
        .padding(.vertical, 14)
    }
}

private extension AnalysisIssueKind {
    var displayName: String {
        switch self {
        case .inaccessible: "Sem acesso"
        case .changedDuringScan: "Alterado durante a análise"
        case .busy: "Em uso"
        case .depthLimit: "Profundidade máxima"
        case .readFailed: "Falha de leitura"
        }
    }
}

#Preview { ContentView() }
