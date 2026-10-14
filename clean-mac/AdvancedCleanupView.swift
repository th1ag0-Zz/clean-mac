import Combine
import SwiftUI

@MainActor
final class AdvancedCleanupViewModel: ObservableObject {
    enum State { case idle, scanning, results, cleaning, complete, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var result: AdvancedResult?
    @Published private(set) var report: AdvancedReport?
    @Published private(set) var error: String?
    @Published var selectedIDs: Set<String> = []
    private let engine = AdvancedCleanupEngine()
    private var task: Task<Void, Never>?

    var selected: [AdvancedCandidate] {
        result?.candidates.filter { selectedIDs.contains($0.id) } ?? []
    }

    var selectedBytes: UInt64 {
        selected.reduce(0) { $0.addingReportingOverflow($1.logicalBytes).overflow ? UInt64.max : $0 + $1.logicalBytes }
    }

    func accept(_ analysis: AdvancedResult) {
        task?.cancel(); result = analysis; selectedIDs = []; report = nil; error = nil; state = .results
    }

    func analyze() {
        task?.cancel()
        error = nil
        report = nil
        selectedIDs = []
        state = .scanning
        task = Task {
            do {
                let scanned = try await engine.analyze()
                try Task.checkCancellation()
                result = scanned
                state = .results
            } catch is CancellationError {
                state = result == nil ? .idle : .results
            } catch {
                self.error = error.localizedDescription
                state = .failed
            }
        }
    }

    func cancel() { task?.cancel() }

    func clean() {
        guard let result, !selectedIDs.isEmpty else { return }
        state = .cleaning
        let selection = selectedIDs
        task = Task {
            do {
                report = try await engine.execute(result, selectedIDs: selection)
                state = .complete
            } catch {
                self.error = error.localizedDescription
                state = .failed
            }
        }
    }
}

struct AdvancedCleanupView: View {
    @ObservedObject var model: AdvancedCleanupViewModel
    @State private var showingConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Limpeza adicional")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Revise sistema, Xcode, Mail, backups, modelos de IA, preferências ilegíveis e versões de documentos.")
                .font(.system(size: 14)).foregroundStyle(AppStyle.muted)
            switch model.state {
            case .idle:
                ActionButton(title: "Analisar áreas adicionais", icon: "magnifyingglass") { model.analyze() }
            case .scanning:
                ProgressView("Analisando áreas adicionais…").tint(AppStyle.mint)
                Button("Cancelar") { model.cancel() }.foregroundStyle(AppStyle.mint)
            case .results:
                results
            case .cleaning:
                ProgressView("Processando itens selecionados…").tint(AppStyle.mint)
            case .complete:
                if let report = model.report {
                    Text("\(report.succeededCount) de \(report.outcomes.count) operações concluídas")
                        .font(.system(size: 20, weight: .semibold))
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(report.outcomes) { outcome in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(outcome.candidate.url.path).font(.system(size: 12, design: .monospaced))
                                Text(outcome.error ?? (outcome.removedVersions ? "Versões anteriores removidas" : "Movido para a Lixeira"))
                                    .font(.system(size: 12)).foregroundStyle(outcome.succeeded ? AppStyle.mint : .orange)
                            }
                        }
                    }
                }
                ActionButton(title: "Analisar novamente", icon: "arrow.clockwise") { model.analyze() }
            case .failed:
                Text(model.error ?? "A análise não pôde ser concluída.").foregroundStyle(.orange)
                ActionButton(title: "Tentar novamente", icon: "arrow.clockwise") { model.analyze() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingConfirmation) { confirmation }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(model.result?.candidates.count ?? 0) itens encontrados")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Analisar novamente") { model.analyze() }.foregroundStyle(AppStyle.mint)
            }
            if let issues = model.result?.issues, !issues.isEmpty {
                DisclosureGroup("\(issues.count) áreas ou itens não acessíveis") {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(issues, id: \.self) { path in
                            Text(path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }.tint(.orange)
            }
            ForEach(AdvancedCategory.allCases, id: \.self) { category in
                let items = model.result?.candidates.filter { $0.category == category } ?? []
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(category.title).font(.system(size: 18, weight: .semibold))
                    if items.isEmpty {
                        Text("Nenhum item acessível encontrado nesta área.")
                            .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                    } else {
                        ForEach(items) { item in
                            Divider()
                            HStack(alignment: .top, spacing: 12) {
                                Toggle(isOn: Binding(
                                    get: { model.selectedIDs.contains(item.id) },
                                    set: { if $0 { model.selectedIDs.insert(item.id) }
                                           else { model.selectedIDs.remove(item.id) } }
                                )) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
                                    .accessibilityLabel("Selecionar \(item.url.lastPathComponent)")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.url.lastPathComponent).font(.system(size: 13, weight: .semibold))
                                    Text(item.url.path).font(.system(size: 10, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text(item.reason).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                                    if item.removesVersions {
                                        Text("\(item.versionCount) versões anteriores")
                                            .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                                    }
                                }
                                Spacer()
                                Text(ByteText.format(item.logicalBytes)).font(.system(size: 12))
                            }
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
            }
            HStack {
                Text("\(model.selected.count) itens · \(ByteText.format(model.selectedBytes)) selecionados")
                Spacer()
                ActionButton(title: "Revisar limpeza", icon: "arrow.right") { showingConfirmation = true }
                    .disabled(model.selected.isEmpty)
            }
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirmar limpeza adicional")
                .font(.system(size: 26, weight: .semibold))
            Text("\(model.selected.count) itens · \(ByteText.format(model.selectedBytes)) estimados")
            Text("Arquivos e pastas irão para a Lixeira. Versões anteriores de documentos serão removidas permanentemente; o documento atual será preservado.")
                .font(.system(size: 13)).foregroundStyle(.orange)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.selected) { item in
                        Text(item.url.path).font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Voltar") { showingConfirmation = false }
                Button("Confirmar e limpar") {
                    showingConfirmation = false
                    model.clean()
                }.disabled(model.selected.isEmpty)
            }
        }
        .padding(28).frame(width: 610, height: 430)
        .background(AppStyle.background).preferredColorScheme(.dark)
    }
}
