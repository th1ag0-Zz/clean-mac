import AppKit
import SwiftUI

/// A single review surface for the four cleanup areas exposed by the reference app.
struct CleanupModuleView: View {
    @ObservedObject var model: AnalysisViewModel
    @ObservedObject var advancedModel: AdvancedCleanupViewModel
    @State private var area: Area = .system
    @State private var search = ""
    @State private var confirmation = false
    @State private var advancedConfirmation = false

    private enum Area: String, CaseIterable, Identifiable {
        case system = "Detritos do sistema", ai = "Acúmulos de IA", mail = "Anexos do Mail", trash = "Lixos"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .system: "internaldrive"
            case .ai: "sparkles"
            case .mail: "envelope"
            case .trash: "trash"
            }
        }
    }
    private let accent = Color(red: 0.35, green: 0.84, blue: 0.63)
    private let reviewAccent = Color(red: 0.10, green: 0.48, blue: 0.32)
    private var scanning: Bool { model.state == .scanning || advancedModel.state == .scanning }
    private var initial: Bool { model.state == .initial && advancedModel.state == .idle && model.trashState == .idle }
    private var busy: Bool { scanning || model.state == .cleaning || advancedModel.state == .cleaning || model.trashState == .emptying }
    private var advancedItems: [AdvancedCandidate] {
        (advancedModel.result?.candidates ?? []).filter { item in
            let matchesArea: Bool
            switch area {
            case .ai: matchesArea = item.category == .aiModels || item.category == .aiCaches
            case .mail: matchesArea = item.category == .mailDownloads
            case .system: matchesArea = ![.aiModels, .aiCaches, .mailDownloads].contains(item.category)
            case .trash: matchesArea = false
            }
            return matchesArea && matches(item.url.path)
        }
    }

    var body: some View {
        Group {
            if initial {
                ModuleLandingView(title: "Limpeza de detritos",
                    subtitle: "Abra espaço para o que importa. Encontre arquivos desnecessários espalhados pelo Mac e revise tudo em um só lugar.",
                    symbol: "opticaldisc.fill", accent: accent,
                    features: [("internaldrive", "Detritos do sistema"), ("sparkles", "Acúmulos de IA"), ("envelope", "Anexos do Mail"), ("trash", "Lixos")],
                    action: analyze)
            } else if scanning {
                ScanOrbitView(title: "Encontrando detritos", detail: model.progress.map { "\($0.category.title) · \($0.scannedEntries) itens verificados" } ?? "Analisando arquivos do sistema, IA e Mail…", progress: nil) {
                    model.cancelAnalysis(); advancedModel.cancel()
                }
            } else {
                review
            }
        }
        .tint(accent)
        .sheet(isPresented: $confirmation) { ConfirmationSheet(model: model) }
        .sheet(isPresented: $advancedConfirmation) { confirmAdvanced }
    }

    private func analyze() {
        model.startAnalysis()
        advancedModel.analyze()
        if model.trashState != .loading && model.trashState != .emptying { model.scanTrash() }
    }
    private func matches(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Limpeza de detritos").font(.system(size: 32, weight: .bold))
                    Text("Escolha o que deseja remover do seu Mac.").foregroundStyle(AppStyle.muted)
                }
                Spacer()
                Button("Analisar novamente", systemImage: "arrow.clockwise", action: analyze).disabled(busy)
            }
            HStack(spacing: 10) {
                ForEach(Area.allCases) { item in
                    Button { area = item; search = "" } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 23)).foregroundStyle(reviewAccent)
                            Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                            Text(areaSummary(item)).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(area == item ? reviewAccent.opacity(0.10) : AppStyle.card, in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(area == item ? reviewAccent.opacity(0.55) : .clear))
                    }.buttonStyle(.plain)
                }
            }.disabled(busy)
            if area == .trash {
                TrashView(model: model)
            } else {
                HStack {
                    Text(area.rawValue).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(AppStyle.muted)
                    TextField("Buscar nos resultados", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                statusMessages
                if model.state == .cleaning || advancedModel.state == .cleaning {
                    ProgressView("Limpando os itens revisados…")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                    if area == .system && model.state != .completed {
                        ForEach(model.result?.groups ?? [], id: \.category) { group in
                            let items = group.candidates.filter { matches($0.relativePath) }
                            if !items.isEmpty { basicGroup(group, items: items) }
                        }
                    }
                    if advancedModel.state != .complete {
                        ForEach(AdvancedCategory.allCases, id: \.self) { category in
                            let items = advancedItems.filter { $0.category == category }
                            if !items.isEmpty { advancedGroup(category, items: items) }
                        }
                    }
                    if visibleCount == 0 && model.state != .completed && advancedModel.state != .complete && model.state != .failed && advancedModel.state != .failed {
                        ContentUnavailableView(search.isEmpty ? "Tudo em ordem por aqui" : "Nenhum resultado", systemImage: search.isEmpty ? "checkmark.circle" : "magnifyingglass", description: Text(search.isEmpty ? "Nenhum item acessível encontrado nesta categoria." : "Tente outro nome ou caminho."))
                            .frame(minHeight: 180)
                    }
                        }
                    }.frame(minHeight: 250, maxHeight: 330)
                    selectionBar
                    if area == .system && !model.excludedPaths.isEmpty {
                        DisclosureGroup("\(model.excludedPaths.count) itens na lista de ignorados") {
                            ForEach(model.excludedPaths.sorted(), id: \.self) { path in
                                HStack {
                                    Text(path).font(.caption).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button("Restaurar") { model.include(path) }
                                }.padding(.vertical, 4)
                            }
                        }.foregroundStyle(AppStyle.muted)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.primary)
        .tint(reviewAccent)
        .environment(\.colorScheme, .light)
    }

    private var visibleCount: Int {
        (area == .system ? (model.result?.candidates.filter { matches($0.relativePath) }.count ?? 0) : 0) + advancedItems.count
    }
    private func areaSummary(_ item: Area) -> String {
        if item == .trash {
            return model.trashState == .loading ? "Analisando…" : ByteText.format(model.trashSnapshot?.totalLogicalBytes ?? 0)
        }
        let items = (advancedModel.result?.candidates ?? []).filter { candidate in
            switch item {
            case .ai: return [.aiCaches, .aiModels].contains(candidate.category)
            case .mail: return candidate.category == .mailDownloads
            case .system: return ![.aiCaches, .aiModels, .mailDownloads].contains(candidate.category)
            case .trash: return false
            }
        }
        let bytes = items.reduce(UInt64(0)) { sum, item in
            let next = sum.addingReportingOverflow(item.logicalBytes)
            return next.overflow ? UInt64.max : next.partialValue
        }
        let total = bytes.addingReportingOverflow(item == .system ? model.result?.foundBytes ?? 0 : 0)
        return ByteText.format(total.overflow ? UInt64.max : total.partialValue)
    }

    @ViewBuilder private var statusMessages: some View {
        if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.orange) }
        if let error = advancedModel.error { Text(error).font(.callout).foregroundStyle(.orange) }
        if area == .system, let report = model.cleanupReport, model.state == .completed {
            Label("\(report.movedCount) itens movidos para a Lixeira · \(ByteText.format(report.movedLogicalBytes))", systemImage: "checkmark.circle.fill").foregroundStyle(reviewAccent)
            ForEach(report.outcomes.filter { !$0.moved }) { outcome in
                Text("\(outcome.candidate.url.lastPathComponent): \(outcome.error ?? "Falha")").font(.caption).foregroundStyle(.orange)
            }
        }
        if let report = advancedModel.report, advancedModel.state == .complete {
            Label("\(report.succeededCount) de \(report.outcomes.count) operações adicionais concluídas", systemImage: "checkmark.circle.fill").foregroundStyle(reviewAccent)
            ForEach(report.outcomes.filter { !$0.succeeded }) { outcome in
                Text("\(outcome.candidate.url.lastPathComponent): \(outcome.error ?? "Falha")").font(.caption).foregroundStyle(.orange)
            }
        }
        let issues = (model.result?.issues.map { $0.relativePath } ?? []) + (advancedModel.result?.issues ?? [])
        if !issues.isEmpty {
            DisclosureGroup("Análise parcial · \(issues.count) itens ou áreas sem acesso") {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, path in
                    Text(path).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.font(.caption).foregroundStyle(.orange)
        }
    }

    private func basicGroup(_ group: AnalysisGroup, items: [AnalysisCandidate]) -> some View {
        DisclosureGroup {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Toggle("Selecionar \(item.url.lastPathComponent)", isOn: Binding(get: { model.selectedPaths.contains(item.relativePath) }, set: { model.setSelected($0, for: item) })).labelsHidden().toggleStyle(.checkbox)
                    fileLabel(item.url, reason: item.reason)
                    Spacer()
                    Text(ByteText.format(item.logicalBytes)).font(.caption).monospacedDigit()
                    Menu {
                        Button("Mostrar no Finder") { model.showInFinder(item) }
                        Button("Ignorar este item") { model.exclude(item) }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                }.padding(.vertical, 9)
            }
        } label: {
            HStack {
                Toggle(group.category.title, isOn: Binding(get: { items.allSatisfy { model.selectedPaths.contains($0.relativePath) } }, set: { selected in items.forEach { model.setSelected(selected, for: $0) } })).toggleStyle(.checkbox)
                Spacer()
                Text(items.count == 1 ? "1 item" : "\(items.count) itens").foregroundStyle(AppStyle.muted).font(.caption)
            }
        }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func advancedGroup(_ category: AdvancedCategory, items: [AdvancedCandidate]) -> some View {
        DisclosureGroup {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Toggle("Selecionar \(item.url.lastPathComponent)", isOn: Binding(get: { advancedModel.selectedIDs.contains(item.id) }, set: { selected in
                        if selected { advancedModel.selectedIDs.insert(item.id) } else { advancedModel.selectedIDs.remove(item.id) }
                    })).labelsHidden().toggleStyle(.checkbox)
                    fileLabel(item.url, reason: item.reason)
                    Spacer()
                    Text(ByteText.format(item.logicalBytes)).font(.caption).monospacedDigit()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).help("Mostrar no Finder")
                }.padding(.vertical, 9)
            }
        } label: {
            HStack {
                Toggle(category.title, isOn: Binding(get: { items.allSatisfy { advancedModel.selectedIDs.contains($0.id) } }, set: { selected in
                    for item in items { if selected { advancedModel.selectedIDs.insert(item.id) } else { advancedModel.selectedIDs.remove(item.id) } }
                })).toggleStyle(.checkbox)
                Spacer()
                Text(items.count == 1 ? "1 item" : "\(items.count) itens").foregroundStyle(AppStyle.muted).font(.caption)
            }
        }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
    }
    private func fileLabel(_ url: URL, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(url.lastPathComponent).font(.system(size: 12, weight: .medium))
            Text(url.path).font(.system(size: 10)).foregroundStyle(AppStyle.muted).lineLimit(1).truncationMode(.middle).help(url.path)
            Text(reason).font(.system(size: 10)).foregroundStyle(AppStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var selectionBar: some View {
        VStack(spacing: 12) {
            if model.selectedCandidates.isEmpty && advancedModel.selected.isEmpty {
                HStack {
                    Text("Nenhum item selecionado").font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                    Spacer()
                    Button("Revisar limpeza") {}.buttonStyle(.borderedProminent).disabled(true)
                }
            }
            if !model.selectedCandidates.isEmpty && model.state != .completed {
                HStack {
                    Text("Detritos: \(model.selectedCandidates.count) itens · \(ByteText.format(model.selectedBytes))").font(.callout)
                    Spacer()
                    Button("Revisar limpeza") { confirmation = true }.buttonStyle(.borderedProminent)
                }
            }
            if !advancedModel.selected.isEmpty && advancedModel.state != .complete {
                HStack {
                    Text("Áreas adicionais: \(advancedModel.selected.count) itens · \(ByteText.format(advancedModel.selectedBytes))").font(.callout)
                    Spacer()
                    Button("Revisar seleção") { advancedConfirmation = true }.buttonStyle(.borderedProminent)
                }
            }
            Text("Arquivos vão para a Lixeira. Versões anteriores de documentos são apagadas permanentemente após confirmação.").font(.caption).foregroundStyle(AppStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.top, 8)
    }
    private var confirmAdvanced: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Revisar limpeza").font(.title2.bold())
            Text("\(advancedModel.selected.count) itens · \(ByteText.format(advancedModel.selectedBytes))")
            Text(advancedModel.selected.contains(where: \.removesVersions) ? "Versões anteriores dos documentos selecionados serão apagadas permanentemente. Os demais arquivos irão para a Lixeira." : "Os arquivos e pastas selecionados serão movidos para a Lixeira.").foregroundStyle(AppStyle.muted)
            ScrollView { LazyVStack(alignment: .leading, spacing: 9) { ForEach(advancedModel.selected) { item in Text(item.url.path).font(.caption).textSelection(.enabled) } } }
            HStack {
                Spacer()
                Button("Cancelar") { advancedConfirmation = false }
                Button("Confirmar limpeza") { advancedConfirmation = false; advancedModel.clean() }.buttonStyle(.borderedProminent).disabled(advancedModel.selected.isEmpty)
            }
        }.padding(28).frame(width: 580, height: 420).background(AppStyle.background)
    }
}
