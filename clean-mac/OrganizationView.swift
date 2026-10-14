import AppKit
import Combine
import SwiftUI

@MainActor
final class OrganizationViewModel: ObservableObject {
    enum State { case idle, scanning, results, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: OrganizationSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var removalMessage: String?
    @Published private(set) var isRemoving = false
    @Published var selectedIDs: Set<String> = []
    private let engine = OrganizationEngine()

    var selectedFiles: [OrganizedFile] {
        guard let snapshot else { return [] }
        let candidates = snapshot.downloads + snapshot.oldFiles + snapshot.duplicateGroups.flatMap(\.files) + snapshot.similarImages.flatMap { [$0.first, $0.second] }
        return Dictionary(candidates.filter { selectedIDs.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.relativePath < $1.relativePath }
    }

    func canSelect(_ file: OrganizedFile) -> Bool {
        guard let snapshot, !selectedIDs.contains(file.id) else { return true }
        return !snapshot.duplicateGroups.contains { group in
            group.files.contains(where: { $0.id == file.id }) && group.files.allSatisfy { $0.id == file.id || selectedIDs.contains($0.id) }
        }
    }

    func accept(_ analysis: OrganizationSnapshot) {
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
        guard let snapshot, !isRemoving, !selectedFiles.isEmpty else { return }
        let files = selectedFiles
        isRemoving = true; removalMessage = nil
        Task {
            do {
                let report = try await engine.moveToTrash(files, duplicateGroups: snapshot.duplicateGroups)
                removalMessage = report.message
                isRemoving = false
                scan()
            } catch { removalMessage = error.localizedDescription; isRemoving = false }
        }
    }
}

struct OrganizationView: View {
    @ObservedObject var model: OrganizationViewModel
    @State private var category: Category = .downloads
    @State private var search = ""
    @State private var reviewing = false
    private enum Category: String, CaseIterable { case downloads = "Downloads", old = "Antigos", duplicates = "Duplicados", similar = "Imagens semelhantes" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Acúmulos").font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Organize downloads, arquivos antigos, cópias idênticas e imagens semelhantes.")
                .foregroundStyle(AppStyle.muted)
            if let message = model.removalMessage { Text(message).foregroundStyle(AppStyle.mint).textSelection(.enabled) }
            switch model.state {
            case .idle: ActionButton(title: "Analisar organização", icon: "square.grid.3x3") { model.scan() }
            case .scanning: ProgressView("Comparando arquivos locais…").tint(AppStyle.mint)
            case .failed:
                Text(model.error ?? "A análise falhou.").foregroundStyle(.orange)
                Button("Tentar novamente") { model.scan() }
            case .results:
                if let snapshot = model.snapshot { results(snapshot) }
            }
        }
        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.isRemoving)
        .sheet(isPresented: $reviewing) {
            PersonalFileReviewSheet(files: model.selectedFiles.map(\.selection)) { model.removeSelected() }
        }
    }

    private func results(_ snapshot: OrganizationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(snapshot.scannedFiles) arquivos examinados").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Analisar novamente") { model.scan() }.buttonStyle(.plain).foregroundStyle(AppStyle.mint)
            }
            Text("Pastas pessoais locais. Links, pacotes, nuvem e outros volumes são ignorados. Os tamanhos são lógicos; clones APFS podem compartilhar espaço.")
                .foregroundStyle(AppStyle.muted)
            if snapshot.inaccessibleLocations > 0 { Text("\(snapshot.inaccessibleLocations) locais não puderam ser lidos.").foregroundStyle(.orange) }
            HStack(spacing: 10) {
                ForEach(snapshot.folders) { folder in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(folder.name).fontWeight(.semibold)
                        Text(ByteText.format(folder.logicalBytes)).foregroundStyle(AppStyle.mint)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Picker("Categoria", selection: $category) { ForEach(Category.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            TextField("Buscar por nome ou caminho", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Text("\(model.selectedFiles.count) selecionados · \(ByteText.format(model.selectedFiles.reduce(0) { $0 &+ $1.logicalBytes }))")
                Button("Limpar seleção") { model.selectedIDs = [] }.disabled(model.selectedIDs.isEmpty)
                Spacer()
                Button("Revisar e mover…") { reviewing = true }.disabled(model.selectedFiles.isEmpty)
            }
            switch category {
            case .downloads:
                fileList(snapshot.downloads, empty: "Nenhum download encontrado.")
            case .old:
                Text("Sem alterações há pelo menos 365 dias. Isso não mede o último acesso.").foregroundStyle(AppStyle.muted)
                fileList(snapshot.oldFiles, empty: "Nenhum arquivo antigo encontrado.")
            case .duplicates:
                Text("Mesmo tamanho e SHA-256. Uma cópia de cada grupo deve ser mantida. Nenhum arquivo é selecionado automaticamente.").foregroundStyle(AppStyle.muted)
                let groups = snapshot.duplicateGroups.filter { $0.files.contains(where: matches) }
                if groups.isEmpty { Text("Nenhum duplicado encontrado.").foregroundStyle(AppStyle.muted) }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.files.count) cópias · até \(ByteText.format(group.possibleSavings)) repetidos").fontWeight(.semibold)
                        ForEach(group.files) { file in fileRow(file) }
                    }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
                }
            case .similar:
                Text("Semelhança visual aproximada. Abra as imagens e compare antes de selecionar.").foregroundStyle(AppStyle.muted)
                let pairs = snapshot.similarImages.filter { matches($0.first) || matches($0.second) }
                if pairs.isEmpty { Text("Nenhuma imagem semelhante encontrada.").foregroundStyle(AppStyle.muted) }
                ForEach(pairs) { pair in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Possível semelhança · distância visual \(pair.distance)/64").fontWeight(.semibold)
                        fileRow(pair.first)
                        fileRow(pair.second)
                    }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
                }
                if snapshot.skippedImages > 0 { Text("\(snapshot.skippedImages) imagens ficaram fora da comparação. Limite: 500 imagens locais de até 40 MB.").foregroundStyle(AppStyle.muted) }
            }
        }
    }

    private func matches(_ file: OrganizedFile) -> Bool { search.isEmpty || file.relativePath.localizedCaseInsensitiveContains(search) }
    private func fileList(_ files: [OrganizedFile], empty: String) -> some View {
        let filtered = files.filter(matches)
        return LazyVStack(spacing: 8) {
            if filtered.isEmpty { Text(empty).foregroundStyle(AppStyle.muted).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(filtered) { file in fileRow(file) }
        }
    }
    private func fileRow(_ file: OrganizedFile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("Selecionar \(file.url.lastPathComponent)", isOn: Binding(get: { model.selectedIDs.contains(file.id) }, set: { selected in
                if selected && model.canSelect(file) { model.selectedIDs.insert(file.id) } else { model.selectedIDs.remove(file.id) }
            })).labelsHidden().toggleStyle(.checkbox).disabled(!model.canSelect(file))
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.url.lastPathComponent).fontWeight(.semibold)
                Text(file.relativePath).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
                Text("\(ByteText.format(file.logicalBytes)) · \(file.modifiedAt.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 11)).foregroundStyle(AppStyle.muted)
            }
            Spacer()
            Button("Abrir") { NSWorkspace.shared.open(file.url) }.buttonStyle(.plain).foregroundStyle(AppStyle.mint)
            Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.buttonStyle(.plain).foregroundStyle(AppStyle.mint)
        }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

import SwiftUI

struct PersonalFileReviewSheet: View {
    let files: [PersonalFileSelection]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Revisar arquivos selecionados").font(.system(size: 24, weight: .semibold))
            Text("\(files.count) arquivos · \(ByteText.format(files.reduce(0) { $0 &+ $1.logicalBytes }))")
            Text("Confira cada caminho. Os arquivos serão movidos para a Lixeira; o espaço só será liberado quando você a esvaziar.")
                .foregroundStyle(AppStyle.muted)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(files) { file in
                        HStack {
                            Text(file.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Text(ByteText.format(file.logicalBytes)).font(.system(size: 11))
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Confirmar e mover para a Lixeira", role: .destructive) { onConfirm(); dismiss() }
                    .disabled(files.isEmpty)
            }
        }
        .padding(28).frame(width: 660, height: 440)
        .background(AppStyle.background).preferredColorScheme(.dark)
    }
}
