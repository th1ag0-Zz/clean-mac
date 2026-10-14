import SwiftUI

struct TrashView: View {
    @ObservedObject var model: AnalysisViewModel
    @State private var showingConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Lixeiras dos discos")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text("Revise os itens antes de apagá-los permanentemente.")
                        .foregroundStyle(AppStyle.muted)
                }
                Spacer()
                Button { model.scanTrash() } label: {
                    Label("Atualizar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain).foregroundStyle(AppStyle.mint)
                .disabled(model.trashState == .emptying)
            }

            switch model.trashState {
            case .idle, .loading:
                ProgressView("Lendo a Lixeira…").tint(AppStyle.mint)
                    .padding(.top, 40)
            case .ready:
                readyContent
            case .emptying:
                VStack(alignment: .leading, spacing: 15) {
                    ProgressView().tint(AppStyle.mint)
                    Text("Esvaziando os itens revisados…")
                        .font(.system(size: 18, weight: .semibold))
                }
                .padding(.top, 40)
            case .finished:
                finishedContent
            case .failed:
                VStack(alignment: .leading, spacing: 15) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36)).foregroundStyle(.orange)
                    Text("Não foi possível concluir a operação")
                        .font(.system(size: 24, weight: .semibold))
                    Text(model.trashError ?? "Atualize a Lixeira e tente novamente.")
                        .foregroundStyle(AppStyle.muted)
                    Button("Analisar novamente") { model.scanTrash() }
                }
                .padding(.top, 40)
            }
        }
        .sheet(isPresented: $showingConfirmation) {
            TrashConfirmationSheet(model: model)
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if let snapshot = model.trashSnapshot {
            HStack(spacing: 14) {
                SummaryCard(title: "Itens na Lixeira", value: "\(snapshot.items.count)",
                            note: "Disco principal e volumes montados", icon: "trash")
                SummaryCard(title: "Tamanho encontrado", value: ByteText.format(snapshot.totalLogicalBytes),
                            note: "Tamanho lógico estimado", icon: "externaldrive")
            }
            if !snapshot.issues.isEmpty {
                Text("Análise parcial: \(snapshot.issues.count) itens não puderam ser medidos com segurança.")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            if snapshot.items.isEmpty {
                Text(snapshot.issues.isEmpty
                     ? "As Lixeiras acessíveis estão vazias."
                     : "Nenhum item pôde ser incluído nesta revisão. Atualize após resolver os problemas de acesso.")
                    .foregroundStyle(AppStyle.muted).padding(.top, 25)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(snapshot.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "doc").foregroundStyle(AppStyle.mint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.system(size: 13, weight: .semibold))
                                Text(item.url.path).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(AppStyle.muted).textSelection(.enabled)
                            }
                            Spacer()
                            Text(ByteText.format(item.logicalBytes))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.vertical, 14)
                        if item.id != snapshot.items.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 20)
                .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))

                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Exclusão permanente")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Esta ação não pode ser desfeita. Novos itens adicionados depois desta revisão não serão incluídos.")
                            .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                    }
                    Spacer()
                    Button("Revisar esvaziamento") { showingConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .padding(20)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var finishedContent: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            Image(systemName: model.trashReport?.failedCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(model.trashReport?.failedCount == 0 ? AppStyle.mint : .orange)
            Text(model.trashReport?.failedCount == 0 ? "Esvaziamento finalizado" : "Esvaziamento parcial")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            if let report = model.trashReport {
                Text("\(report.deletedCount) itens removidos · \(report.failedCount) falhas")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(ByteText.format(report.estimatedRemovedBytes)) de dados alocados removidos, estimados. Espaço efetivamente liberado: não mensurável.")
                    .foregroundStyle(AppStyle.muted)
                ForEach(report.outcomes) { outcome in
                    HStack(alignment: .top) {
                        Image(systemName: outcome.deleted ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(outcome.deleted ? AppStyle.mint : .orange)
                        Text(outcome.path).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Text(outcome.deleted ? "Apagado" : (outcome.error ?? "Falha"))
                            .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                    }
                }
            }
            ActionButton(title: "Atualizar Lixeira", icon: "arrow.clockwise") { model.scanTrash() }
        }
        .padding(.top, 35)
    }
}

private struct TrashConfirmationSheet: View {
    @ObservedObject var model: AnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34)).foregroundStyle(.orange)
            Text("Esvaziar a Lixeira?")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("\(model.trashSnapshot?.items.count ?? 0) itens · \(ByteText.format(model.trashSnapshot?.totalLogicalBytes ?? 0)) de tamanho lógico estimado")
                .font(.system(size: 15, weight: .semibold))
            Text("Os itens desta revisão serão apagados permanentemente. Não será possível colocá-los de volta. Itens alterados desde a análise serão ignorados.")
                .font(.system(size: 13)).foregroundStyle(AppStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            if ScanScope.isFixture {
            Text("Nesta sessão, apenas a Lixeira da pasta de teste será alterada.")
                .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Esvaziar definitivamente", role: .destructive) {
                    model.emptyTrash()
                    dismiss()
                }
                .disabled(model.trashSnapshot?.items.isEmpty ?? true)
            }
        }
        .padding(28).frame(width: 550, height: 330)
        .background(AppStyle.background).preferredColorScheme(.dark)
    }
}
