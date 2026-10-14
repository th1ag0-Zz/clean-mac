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
    @Published private(set) var updateResults: [String: String] = [:]
    @Published private(set) var checkingUpdates = false
    private let engine = ApplicationsEngine()
    private var task: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

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
        task?.cancel(); snapshot = analysis; selectedApps = []; selectedData = []; selectedResidues = []; selectedInstallers = []
        report = nil; error = nil; state = .results
    }

    func scan() {
        task?.cancel()
        updateTask?.cancel()
        state = .scanning
        error = nil
        report = nil
        selectedApps = []
        selectedData = []
        selectedResidues = []
        selectedInstallers = []
        updateResults = [:]
        checkingUpdates = false
        task = Task {
            do {
                let found = try await engine.scan()
                try Task.checkCancellation()
                snapshot = found
                state = .results
            } catch is CancellationError {
                state = snapshot == nil ? .idle : .results
            } catch {
                self.error = error.localizedDescription
                state = .failed
            }
        }
    }

    func clean() {
        guard let snapshot, selectedCount > 0 else { return }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Aplicativos")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Revise aplicativos, possíveis resíduos e instaladores antigos. Nada vem selecionado.")
                .font(.system(size: 14)).foregroundStyle(AppStyle.muted)
            switch model.state {
            case .idle:
                ActionButton(title: "Analisar aplicativos", icon: "magnifyingglass") { model.scan() }
            case .scanning:
                ProgressView("Analisando aplicativos…").tint(AppStyle.mint)
            case .results:
                results
            case .cleaning:
                ProgressView("Movendo itens selecionados para a Lixeira…").tint(AppStyle.mint)
            case .complete:
                if let report = model.report {
                    Text("\(report.succeededCount) de \(report.outcomes.count) itens movidos")
                        .font(.system(size: 20, weight: .semibold))
                    ForEach(report.outcomes) { outcome in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(outcome.path).font(.system(size: 12, design: .monospaced))
                            Text(outcome.error ?? "Movido para a Lixeira")
                                .font(.system(size: 11))
                                .foregroundStyle(outcome.succeeded ? AppStyle.mint : .orange)
                        }
                    }
                }
                ActionButton(title: "Analisar novamente", icon: "arrow.clockwise") { model.scan() }
            case .failed:
                Text(model.error ?? "Não foi possível concluir a operação.").foregroundStyle(.orange)
                ActionButton(title: "Tentar novamente", icon: "arrow.clockwise") { model.scan() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $confirming) { confirmation }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(model.snapshot?.apps.count ?? 0) aplicativos encontrados")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Analisar novamente") { model.scan() }.foregroundStyle(AppStyle.mint)
            }
            section(title: "Desinstalação e seleção em lote", icon: "square.stack.3d.up") {
                Text("Selecione um ou vários apps. Dados associados aparecem abaixo de cada app e exigem seleção separada. Apps em uso não serão movidos.")
                    .foregroundStyle(AppStyle.muted)
                if let apps = model.snapshot?.apps, apps.isEmpty {
                    Text("Nenhum app elegível encontrado em Aplicativos.").foregroundStyle(AppStyle.muted)
                } else {
                    ForEach(model.snapshot?.apps ?? []) { app in
                        Divider()
                        HStack(alignment: .top, spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { model.selectedApps.contains(app.id) },
                                set: { model.setApp($0, app: app) }
                            )) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
                                .accessibilityLabel("Selecionar \(app.name)")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(app.name).font(.system(size: 15, weight: .semibold))
                                Text("\(app.bundleID) · versão \(app.version)")
                                    .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                                Text(app.item.url.path).font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                if !app.associated.isEmpty {
                                    DisclosureGroup("\(app.associated.count) dados associados") {
                                        ForEach(app.associated) { item in
                                            itemToggle(item.url.path, selected: Binding(
                                                get: { model.selectedData.contains(item.id) },
                                                set: { if $0 { model.selectedData.insert(item.id) }
                                                       else { model.selectedData.remove(item.id) } }
                                            ))
                                            .disabled(!model.selectedApps.contains(app.id))
                                        }
                                    }.tint(AppStyle.mint)
                                }
                            }
                        }
                    }
                }
            }
            section(title: "Possíveis resíduos", icon: "tray") {
                Text("Pastas e preferências com identificador de app sem instalação encontrada. Confira o caminho: outro usuário ou uma instalação fora de Aplicativos pode ainda precisar desses dados.")
                    .foregroundStyle(AppStyle.muted)
                if model.snapshot?.residues.isEmpty != false {
                    Text("Nenhum possível resíduo encontrado.").foregroundStyle(AppStyle.muted)
                }
                ForEach(model.snapshot?.residues ?? []) { item in
                    itemToggle(item.url.path, selected: Binding(
                        get: { model.selectedResidues.contains(item.id) },
                        set: { if $0 { model.selectedResidues.insert(item.id) }
                               else { model.selectedResidues.remove(item.id) } }
                    ))
                }
            }
            section(title: "Instaladores antigos", icon: "shippingbox") {
                Text("Arquivos .dmg e .pkg diretamente em Downloads, sem alterações há pelo menos 30 dias. Usa a mesma regra da análise principal.")
                    .foregroundStyle(AppStyle.muted)
                if model.snapshot?.installers.isEmpty != false {
                    Text("Nenhum instalador antigo encontrado.").foregroundStyle(AppStyle.muted)
                }
                ForEach(model.snapshot?.installers ?? []) { item in
                    itemToggle("\(item.url.path) · \(ByteText.format(item.logicalBytes))", selected: Binding(
                        get: { model.selectedInstallers.contains(item.id) },
                        set: { if $0 { model.selectedInstallers.insert(item.id) }
                               else { model.selectedInstallers.remove(item.id) } }
                    ))
                }
            }
            HStack {
                Text("\(model.selectedCount) itens selecionados")
                Spacer()
                ActionButton(title: "Revisar remoção", icon: "arrow.right") { confirming = true }
                    .disabled(model.selectedCount == 0)
            }
        }
    }

    private func section<Content: View>(title: String, icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 18, weight: .semibold))
            content()
        }
        .font(.system(size: 12))
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func itemToggle(_ label: String, selected: Binding<Bool>) -> some View {
        Toggle(isOn: selected) {
            Text(label).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        }.toggleStyle(.checkbox)
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
