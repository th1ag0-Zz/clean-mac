import AppKit
import SwiftUI

struct ActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                Image(systemName: icon)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background(
                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.10)],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let note: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(AppStyle.mint)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(note).font(.system(size: 10)).foregroundStyle(AppStyle.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 114, alignment: .leading)
        .padding(20)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 19))
        .accessibilityElement(children: .combine)
    }
}

struct ExclusionsSheet: View {
    @ObservedObject var model: AnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Exclusões")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                Button("Fechar") { dismiss() }
            }
            Text("Estes caminhos ficam fora das próximas análises. Remover uma exclusão inicia uma nova análise.")
                .font(.system(size: 13)).foregroundStyle(AppStyle.muted)
            if model.excludedPaths.isEmpty {
                ContentUnavailableView("Nenhuma exclusão", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Itens ignorados aparecerão aqui."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.excludedPaths.sorted(), id: \.self) { path in
                            HStack {
                                Text(path).font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                Button("Remover") { model.include(path) }
                            }
                            .padding(12)
                            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding(28).frame(width: 570, height: 400)
        .background(AppStyle.background).preferredColorScheme(.dark)
    }
}

struct ConfirmationSheet: View {
    @ObservedObject var model: AnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checklist").font(.system(size: 31)).foregroundStyle(AppStyle.mint)
            Text("Revisar operação")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("\(model.selectedCandidates.count) itens · \(ByteText.format(model.selectedBytes)) de tamanho lógico estimado")
                .font(.system(size: 15, weight: .medium))
            if ScanScope.isFixture {
            Text("Destino: .Trash da home de teste. Os arquivos desta operação pertencem à pasta de teste.")
                .font(.system(size: 13)).foregroundStyle(AppStyle.muted)
            } else {
            Text("Destino: Lixeira do macOS. Mover arquivos para a Lixeira não libera espaço imediatamente.")
                .font(.system(size: 13)).foregroundStyle(AppStyle.muted)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(model.selectedCandidates) { candidate in
                        HStack {
                            Text(candidate.relativePath)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text(ByteText.format(candidate.logicalBytes))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .frame(maxHeight: 160)
            HStack {
                Spacer()
                Button("Voltar à revisão") { dismiss() }
                Button("Confirmar e mover") {
                    model.performCleanup()
                    dismiss()
                }
                .disabled(model.selectedCandidates.isEmpty)
            }
        }
        .padding(28).frame(width: 570, height: 440)
        .background(AppStyle.background).preferredColorScheme(.dark)
    }
}

enum ByteText {
    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
}
