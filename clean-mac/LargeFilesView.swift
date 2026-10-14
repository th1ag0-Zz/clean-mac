import AppKit
import Combine
import SwiftUI

@MainActor
final class LargeFilesViewModel: ObservableObject {
    enum State { case idle, scanning, results, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: LargeFilesSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var removalMessage: String?
    @Published private(set) var isRemoving = false
    @Published var selectedIDs: Set<String> = []
    private let engine = LargeFilesEngine()
    var selectedFiles: [LargeFile] { snapshot?.files.filter { selectedIDs.contains($0.id) } ?? [] }

    func accept(_ analysis: LargeFilesSnapshot) {
        snapshot = analysis; selectedIDs = []; error = nil; state = .results
    }

    func scan() {
        guard state != .scanning else { return }
        state = .scanning; error = nil; snapshot = nil; selectedIDs = []
        Task {
            do { snapshot = try await engine.scan(); state = .results }
            catch { self.error = error.localizedDescription; state = .failed }
        }
    }
    func removeSelected() {
        guard !isRemoving, !selectedFiles.isEmpty else { return }
        let files = selectedFiles
        isRemoving = true
        Task {
            do {
                let result = try await engine.moveToTrash(files)
                removalMessage = result.message; isRemoving = false; scan()
            } catch { removalMessage = error.localizedDescription; isRemoving = false }
        }
    }
}

struct LargeFilesView: View {
    @ObservedObject var model: LargeFilesViewModel
    @State private var search = ""
    @State private var minimumMB = 100
    @State private var onlyOld = false
    @State private var reviewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Arquivos grandes").font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Encontre arquivos de 100 MB ou mais, revise e mova os escolhidos para a Lixeira.").foregroundStyle(AppStyle.muted)
            if let message = model.removalMessage { Text(message).foregroundStyle(AppStyle.mint) }
            switch model.state {
            case .idle: ActionButton(title: "Analisar arquivos grandes", icon: "magnifyingglass") { model.scan() }
            case .scanning: ProgressView("Analisando pastas pessoais…").tint(AppStyle.mint)
            case .failed:
                Text(model.error ?? "Não foi possível analisar os arquivos.").foregroundStyle(.orange)
                Button("Tentar novamente") { model.scan() }
            case .results:
                if let snapshot = model.snapshot { results(snapshot) }
            }
        }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.isRemoving)
            .sheet(isPresented: $reviewing) {
                PersonalFileReviewSheet(files: model.selectedFiles.map(\.selection)) { model.removeSelected() }
            }
    }

    private func results(_ snapshot: LargeFilesSnapshot) -> some View {
        let files = snapshot.files.filter {
            (search.isEmpty || $0.relativePath.localizedCaseInsensitiveContains(search)) &&
            $0.logicalBytes >= UInt64(minimumMB) * 1_024 * 1_024 &&
            (!onlyOld || Date.now.timeIntervalSince($0.modifiedAt) >= 365 * 86_400)
        }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(snapshot.files.count) arquivos grandes · \(snapshot.scannedFiles) examinados").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Analisar novamente") { model.scan() }.buttonStyle(.plain).foregroundStyle(AppStyle.mint)
            }
            Text("Pastas pessoais locais. Links, pacotes, nuvem e outros volumes são ignorados. Tamanhos lógicos e ocupados podem incluir espaço compartilhado por clones APFS.").foregroundStyle(AppStyle.muted)
            if snapshot.inaccessibleLocations > 0 { Text("\(snapshot.inaccessibleLocations) locais não puderam ser lidos.").foregroundStyle(.orange) }
            HStack {
                TextField("Buscar por nome ou caminho", text: $search).textFieldStyle(.roundedBorder)
                Picker("A partir de", selection: $minimumMB) {
                    Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1024); Text("5 GB").tag(5120)
                }.frame(width: 185)
                Toggle("Antigos (365 dias)", isOn: $onlyOld).toggleStyle(.checkbox)
            }
            HStack {
                Text("\(model.selectedFiles.count) selecionados · \(ByteText.format(model.selectedFiles.reduce(0) { $0 &+ $1.logicalBytes }))")
                Button("Limpar seleção") { model.selectedIDs = [] }.disabled(model.selectedIDs.isEmpty)
                Spacer()
                Button("Revisar e mover…") { reviewing = true }.disabled(model.selectedFiles.isEmpty)
            }
            if files.isEmpty { Text("Nenhum arquivo corresponde aos filtros.").foregroundStyle(AppStyle.muted) }
            LazyVStack(spacing: 8) {
                ForEach(files) { file in
                    HStack(spacing: 12) {
                        Toggle("Selecionar \(file.url.lastPathComponent)", isOn: Binding(get: { model.selectedIDs.contains(file.id) }, set: {
                            if $0 { model.selectedIDs.insert(file.id) } else { model.selectedIDs.remove(file.id) }
                        })).labelsHidden().toggleStyle(.checkbox)
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(file.url.lastPathComponent).font(.system(size: 14, weight: .semibold))
                            Text(file.relativePath).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
                            Text("\(ByteText.format(file.logicalBytes)) · ocupado: ~\(ByteText.format(file.allocatedBytes)) · \(file.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                        }
                        Spacer()
                        Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.buttonStyle(.plain).foregroundStyle(AppStyle.mint)
                    }.padding(14).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}
