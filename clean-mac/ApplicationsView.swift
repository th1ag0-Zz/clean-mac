import AppKit
import Combine
import SwiftUI

@MainActor
final class ApplicationsViewModel: ObservableObject {
    enum State { case idle, scanning, results, cleaning, complete, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: ApplicationsSnapshot?
    @Published private(set) var report: ApplicationsReport?
    @Published private(set) var error: String?
    @Published var selectedApps: Set<String> = []
    @Published var selectedData: Set<String> = []
    @Published var selectedResidues: Set<String> = []
    @Published var selectedInstallers: Set<String> = []
    private let engine = ApplicationsEngine()
    private var task: Task<Void, Never>?
    private var scanID = UUID()

    var selectedCount: Int {
        selectedApps.count + selectedData.count + selectedResidues.count + selectedInstallers.count
    }

    var selectedPaths: [String] {
        guard let snapshot else { return [] }
        return (snapshot.apps.filter { selectedApps.contains($0.id) }.map { $0.item.url.path } +
                snapshot.apps.flatMap(\.associated).filter { selectedData.contains($0.id) }.map { $0.url.path } +
                snapshot.residues.filter { selectedResidues.contains($0.id) }.map { $0.url.path } +
                snapshot.installers.filter { selectedInstallers.contains($0.id) }.map { $0.url.path }).sorted()
    }

    func setApp(_ selected: Bool, app: ManagedApp) {
        if selected { selectedApps.insert(app.id) }
        else {
            selectedApps.remove(app.id)
            selectedData.subtract(app.associated.map(\.id))
        }
    }

    func accept(_ analysis: ApplicationsSnapshot) {
        guard state != .cleaning else { return }
        scanID = UUID(); task?.cancel(); task = nil; snapshot = analysis; selectedApps = []; selectedData = []; selectedResidues = []; selectedInstallers = []
        report = nil; error = nil; state = .results
    }

    func scan() {
        guard state != .cleaning else { return }
        scanID = UUID()
        let currentScan = scanID
        task?.cancel()
        state = .scanning
        error = nil
        report = nil
        selectedApps = []
        selectedData = []
        selectedResidues = []
        selectedInstallers = []
        task = Task {
            do {
                let found = try await engine.scan()
                try Task.checkCancellation()
                guard scanID == currentScan else { return }
                snapshot = found
                state = .results
            } catch is CancellationError {
                guard scanID == currentScan else { return }
                state = snapshot == nil ? .idle : .results
            } catch {
                guard scanID == currentScan else { return }
                self.error = error.localizedDescription
                state = .failed
            }
        }
    }

    func cancel() {
        guard state == .scanning else { return }
        scanID = UUID()
        task?.cancel(); task = nil
        state = snapshot == nil ? .idle : .results
    }

    func clean() {
        guard state == .results, let snapshot, selectedCount > 0 else { return }
        state = .cleaning
        let appIDs = selectedApps
        let dataIDs = selectedData
        let residueIDs = selectedResidues
        let installerIDs = selectedInstallers
        task = Task {
            do {
                report = try await engine.execute(snapshot, appIDs: appIDs, dataIDs: dataIDs,
                                                  residueIDs: residueIDs, installerIDs: installerIDs)
                state = .complete
            } catch {
                self.error = error.localizedDescription
                state = .failed
            }
        }
    }


}

struct ApplicationsView: View {
    @ObservedObject var model: ApplicationsViewModel
    @State private var confirming = false
    @State private var showingManager = false
    @State private var category: Category = .apps
    @State private var search = ""
    @State private var ascendingName = true
    private enum Category: String, CaseIterable {
        case apps = "Desinstalador", residues = "Arquivos de sobras", installers = "Instaladores"
        var symbol: String {
            switch self { case .apps: "square.stack.3d.up"; case .residues: "puzzlepiece.extension"; case .installers: "shippingbox" }
        }
    }

    var body: some View {
        Group {
            if model.state == .idle {
                ModuleLandingView(title: "Aplicativos", subtitle: "Um novo começo para os seus aplicativos.\nRemova o que não usa e os arquivos que ficaram para trás.", symbol: "app.badge.fill", accent: .blue,
                                  features: [("square.stack.3d.up", "Desinstalador de apps"), ("puzzlepiece.extension", "Arquivos de sobras"), ("shippingbox", "Remova instaladores")]) { startScan() }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        if showingManager && model.state == .results {
                            Button { showingManager = false } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)) }.buttonStyle(.plain).help("Voltar ao resumo")
                        }
                        Text("Aplicativos").font(.system(size: 30, weight: .bold))
                        Spacer()
                        if model.state == .results { Button("Analisar novamente", systemImage: "arrow.clockwise") { startScan() }.buttonStyle(.plain).foregroundStyle(AppStyle.muted) }
                    }
                    switch model.state {
                    case .idle: EmptyView()
                    case .scanning:
                        ScanOrbitView(title: "Analisando aplicativos…", detail: "Localizando aplicativos, arquivos associados e instaladores.", progress: nil, cancel: model.cancel)
                    case .cleaning: progress("Desinstalando…", detail: "Movendo os itens selecionados para a Lixeira.")
                    case .results:
                        if showingManager { results } else { overview }
                    case .complete:
                        if let report = model.report {
                            Label("\(report.succeededCount) itens movidos para a Lixeira", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 23, weight: .semibold)).foregroundStyle(AppStyle.mint)
                            ForEach(report.outcomes.filter { !$0.succeeded }) { outcome in
                                Text("\(outcome.path): \(outcome.error ?? "Não foi possível remover")").font(.system(size: 12)).foregroundStyle(.orange)
                            }
                        }
                        ActionButton(title: "Analisar novamente", icon: "arrow.clockwise") { startScan() }
                    case .failed:
                        Text(model.error ?? "Não foi possível concluir a operação.").foregroundStyle(.orange)
                        ActionButton(title: "Tentar novamente", icon: "arrow.clockwise") { startScan() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: model.state) { _, state in
            if state == .scanning { showingManager = false }
        }
        .sheet(isPresented: $confirming) { confirmation }
    }

    private func startScan() {
        showingManager = false
        search = ""
        model.scan()
    }

    private func manage(_ selected: Category) {
        category = selected
        search = ""
        showingManager = true
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Color.blue.opacity(0.18)).frame(width: 110, height: 110)
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 51)).foregroundStyle(.blue.gradient)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(count(.apps) == 1 ? "1 aplicativo encontrado no Mac" : "\(count(.apps)) aplicativos encontrados no Mac")
                        .font(.system(size: 27, weight: .semibold))
                    Text("Revise seus aplicativos e remova o que não precisa.")
                        .font(.system(size: 13)).foregroundStyle(AppStyle.muted)
                    Button("Gerenciar Aplicativos") { manage(.apps) }
                        .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 25)
            HStack(alignment: .top, spacing: 16) {
                overviewCard(.residues, detail: "Arquivos deixados por aplicativos que não foram encontrados no Mac.")
                overviewCard(.installers, detail: "Instaladores antigos em Downloads que você pode revisar e remover.")
            }
            Spacer(minLength: 20)
        }.frame(maxWidth: .infinity, minHeight: 435, alignment: .topLeading)
    }

    private func overviewCard(_ item: Category, detail: String) -> some View {
        Button { manage(item) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: item.symbol).font(.system(size: 28)).foregroundStyle(.blue)
                Text(item.rawValue).font(.system(size: 18, weight: .semibold))
                Text("\(count(item)) itens encontrados").font(.system(size: 22, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(AppStyle.muted).fixedSize(horizontal: false, vertical: true)
                Label("Revisar", systemImage: "arrow.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.blue)
            }.padding(23).frame(maxWidth: .infinity, minHeight: 225, alignment: .topLeading)
                .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private func progress(_ title: String, detail: String) -> some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large).tint(.blue)
            Text(title).font(.system(size: 23, weight: .semibold))
            Text(detail).foregroundStyle(AppStyle.muted)
        }.frame(maxWidth: .infinity, minHeight: 380)
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showingManager = false } label: { Label("Voltar", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text("Gerenciador de Aplicativos").font(.system(size: 15, weight: .semibold))
                Spacer()
                Menu {
                    Button("Nome: A–Z") { ascendingName = true }
                    Button("Nome: Z–A") { ascendingName = false }
                } label: {
                    Label(ascendingName ? "Nome: A–Z" : "Nome: Z–A", systemImage: "arrow.up.arrow.down")
                }.menuStyle(.borderlessButton).fixedSize()
            }.padding(18)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Category.allCases, id: \.self) { item in
                        Button { category = item; search = "" } label: {
                            HStack(spacing: 9) {
                                Image(systemName: item.symbol).frame(width: 19)
                                Text(item.rawValue)
                                Spacer(minLength: 4)
                                Text("\(count(item))").foregroundStyle(AppStyle.muted)
                            }.font(.system(size: 12, weight: .medium)).padding(11)
                                .background(category == item ? Color.purple.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }.padding(12).frame(width: 185)
                Divider()
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(category.rawValue).font(.system(size: 20, weight: .semibold))
                        Spacer()
                        TextField("Buscar", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 190)
                    }
                    Text(categoryDescription).font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            switch category {
                            case .apps:
                                let apps = (model.snapshot?.apps ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted {
                                    let order = $0.name.localizedStandardCompare($1.name)
                                    return ascendingName ? order == .orderedAscending : order == .orderedDescending
                                }
                                if apps.isEmpty { emptyState }
                                ForEach(apps) { app in appRow(app); Divider().padding(.leading, 42) }
                            case .residues:
                                let items = (model.snapshot?.residues ?? []).filter { search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search) }.sorted {
                                    let order = $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                                    return ascendingName ? order == .orderedAscending : order == .orderedDescending
                                }
                                if items.isEmpty { emptyState }
                                ForEach(items) { item in
                                    itemToggle(item.url, detail: item.relativePath, selected: Binding(get: { model.selectedResidues.contains(item.id) }, set: { if $0 { model.selectedResidues.insert(item.id) } else { model.selectedResidues.remove(item.id) } }))
                                    Divider()
                                }
                            case .installers:
                                let items = (model.snapshot?.installers ?? []).filter { search.isEmpty || $0.url.path.localizedCaseInsensitiveContains(search) }.sorted {
                                    let order = $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                                    return ascendingName ? order == .orderedAscending : order == .orderedDescending
                                }
                                if items.isEmpty { emptyState }
                                ForEach(items) { item in
                                    itemToggle(item.url, detail: ByteText.format(item.logicalBytes), selected: Binding(get: { model.selectedInstallers.contains(item.id) }, set: { if $0 { model.selectedInstallers.insert(item.id) } else { model.selectedInstallers.remove(item.id) } }))
                                    Divider()
                                }
                            }
                        }
                    }.frame(minHeight: 290, maxHeight: 420)
                }.padding(20).frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Text(model.selectedCount == 1 ? "1 item selecionado" : "\(model.selectedCount) itens selecionados").font(.system(size: 13)).foregroundStyle(AppStyle.muted)
                Spacer()
                Button(category == .apps ? "Desinstalar…" : "Remover…") { confirming = true }
                    .buttonStyle(.borderedProminent).tint(.pink).controlSize(.large).disabled(model.selectedCount == 0)
            }.padding(18)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.primary)
        .tint(.purple)
        .environment(\.colorScheme, .light)
    }

    private func count(_ category: Category) -> Int {
        switch category {
        case .apps: model.snapshot?.apps.count ?? 0
        case .residues: model.snapshot?.residues.count ?? 0
        case .installers: model.snapshot?.installers.count ?? 0
        }
    }
    private var categoryDescription: String {
        switch category {
        case .apps: "Selecione os apps e revise os dados associados antes de desinstalar."
        case .residues: "Dados sem aplicativo correspondente. Confira se outra instalação ainda precisa deles."
        case .installers: "Instaladores em Downloads sem alterações há pelo menos 30 dias."
        }
    }
    private var emptyState: some View {
        Label(search.isEmpty ? "Nenhum item encontrado" : "Nenhum resultado para esta busca", systemImage: "checkmark.circle")
            .foregroundStyle(AppStyle.muted).padding(.vertical, 35).frame(maxWidth: .infinity)
    }
    private func appRow(_ app: ManagedApp) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Selecionar \(app.name)", isOn: Binding(get: { model.selectedApps.contains(app.id) }, set: { model.setApp($0, app: app) }))
                .toggleStyle(.checkbox).labelsHidden().padding(.top, 12)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.item.url.path)).resizable().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.name).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(app.version).font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                }
                Text(app.item.url.deletingLastPathComponent().path).font(.system(size: 11)).foregroundStyle(AppStyle.muted).lineLimit(1).truncationMode(.middle)
                if !app.associated.isEmpty {
                    DisclosureGroup("\(app.associated.count) arquivos e pastas associados") {
                        ForEach(app.associated) { item in
                            Toggle(item.relativePath, isOn: Binding(get: { model.selectedData.contains(item.id) }, set: { if $0 { model.selectedData.insert(item.id) } else { model.selectedData.remove(item.id) } }))
                                .toggleStyle(.checkbox).font(.system(size: 11)).disabled(!model.selectedApps.contains(app.id)).padding(.vertical, 3)
                        }
                    }.font(.system(size: 11)).tint(.purple)
                }
            }
        }.padding(.vertical, 12)
    }
    private func itemToggle(_ url: URL, detail: String, selected: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Toggle("Selecionar \(url.lastPathComponent)", isOn: selected).toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(AppStyle.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).help("Mostrar no Finder")
        }.padding(.vertical, 11).help(url.path)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirmar remoção")
                .font(.system(size: 26, weight: .semibold))
            Text("\(model.selectedCount) itens serão movidos para a Lixeira. Feche os aplicativos selecionados e confira os dados associados; configurações e dados podem ser necessários em outra instalação.")
                .font(.system(size: 13)).foregroundStyle(.orange)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.selectedPaths, id: \.self) { path in
                        Text(path).font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Voltar") { confirming = false }
                Button("Confirmar e mover") {
                    confirming = false
                    model.clean()
                }
            }
        }
        .padding(28).frame(width: 650, height: 440)
        .background(AppStyle.background).preferredColorScheme(.dark)
    }
}
