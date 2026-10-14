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
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()

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
        guard !isRemoving else { return }
        scanID = UUID(); scanTask?.cancel(); scanTask = nil
        snapshot = analysis; selectedIDs = []; error = nil; state = .results
    }

    func scan() {
        guard !isRemoving else { return }
        scanID = UUID()
        let currentScan = scanID
        scanTask?.cancel()
        state = .scanning; error = nil; selectedIDs = []
        scanTask = Task {
            do {
                let found = try await engine.scan()
                try Task.checkCancellation()
                guard scanID == currentScan else { return }
                snapshot = found; state = .results
            } catch is CancellationError {
                guard scanID == currentScan else { return }
                state = snapshot == nil ? .idle : .results
            } catch {
                guard scanID == currentScan else { return }
                self.error = error.localizedDescription; state = .failed
            }
        }
    }

    func cancel() {
        guard state == .scanning else { return }
        scanID = UUID()
        scanTask?.cancel(); scanTask = nil
        state = snapshot == nil ? .idle : .results
    }

    func removeSelected() {
        guard state == .results, let snapshot, !isRemoving, !selectedFiles.isEmpty else { return }
        let files = selectedFiles
        isRemoving = true; removalMessage = nil
        Task {
            do {
                let report = try await engine.moveToTrash(files, duplicateGroups: snapshot.duplicateGroups)
                removalMessage = report.message
                self.snapshot = nil
                selectedIDs = []
                isRemoving = false
                scan()
            } catch { removalMessage = error.localizedDescription; isRemoving = false }
        }
    }
}

struct OrganizationView: View {
    @ObservedObject var model: OrganizationViewModel
    var openLargeFiles: (() -> Void)? = nil
    var openPhotos: (() -> Void)? = nil
    @State private var category: Category = .downloads
    @State private var search = ""
    @State private var reviewing = false
    private enum Category: String, CaseIterable { case downloads = "Downloads", old = "Antigos", duplicates = "Duplicatas", similar = "Imagens similares" }

    var body: some View {
        Group {
            if model.state == .idle {
                VStack(spacing: 0) {
                    ModuleLandingView(title: "Acúmulos", subtitle: "Abra espaço para o que importa.\nEncontre arquivos grandes, duplicatas e downloads esquecidos.", symbol: "folder.fill", accent: .teal,
                                      features: [("doc", "Arquivos grandes"), ("doc.on.doc", "Duplicatas"), ("photo.on.rectangle", "Imagens similares"), ("tray.full", "Downloads")]) { model.scan() }
                    relatedTools
                }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Acúmulos").font(.system(size: 30, weight: .bold))
                        Spacer()
                        if model.state == .results { Button("Analisar novamente", systemImage: "arrow.clockwise") { model.scan() }.buttonStyle(.plain).foregroundStyle(AppStyle.muted) }
                    }
                    if let message = model.removalMessage { Text(message).foregroundStyle(AppStyle.mint).textSelection(.enabled) }
                    switch model.state {
                    case .idle: EmptyView()
                    case .scanning:
                        ScanOrbitView(title: "Encontrando acúmulos…", detail: "Comparando seus arquivos e imagens locais.", progress: nil, cancel: model.cancel)
                    case .failed:
                        Text(model.error ?? "A análise falhou.").foregroundStyle(.orange)
                        Button("Tentar novamente") { model.scan() }
                    case .results:
                        if let snapshot = model.snapshot { results(snapshot) }
                        relatedTools
                    }
                }
            }
        }
        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.isRemoving)
        .sheet(isPresented: $reviewing) {
            PersonalFileReviewSheet(files: model.selectedFiles.map(\.selection)) { model.removeSelected() }
        }
    }

    private var relatedTools: some View {
        HStack(spacing: 22) {
            if let openLargeFiles {
                Button(action: openLargeFiles) { Label("Arquivos grandes", systemImage: "doc") }
            }
            if let openPhotos {
                Button(action: openPhotos) { Label("Biblioteca de Fotos", systemImage: "photo.on.rectangle.angled") }
            }
        }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(AppStyle.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    private func results(_ snapshot: OrganizationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(Category.allCases, id: \.self) { item in
                    Button { category = item; search = "" } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: symbol(item)).font(.system(size: 22)).foregroundStyle(category == item ? Color.teal : AppStyle.muted)
                            Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                            Text("\(count(item, snapshot: snapshot)) itens").font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(category == item ? Color.teal.opacity(0.12) : AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(category == item ? Color.teal.opacity(0.6) : Color.clear))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Text("\(snapshot.scannedFiles) arquivos examinados").foregroundStyle(AppStyle.muted)
                Spacer()
                TextField("Buscar por nome ou caminho", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 250)
            }
            if snapshot.inaccessibleLocations > 0 { Text("\(snapshot.inaccessibleLocations) locais não puderam ser lidos.").foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    switch category {
                    case .downloads:
                        fileList(snapshot.downloads, empty: "Nenhum download encontrado.")
                    case .old:
                        Text("Sem alterações há pelo menos 365 dias. Isso não mede o último acesso.").foregroundStyle(AppStyle.muted)
                        fileList(snapshot.oldFiles, empty: "Nenhum arquivo antigo encontrado.")
                    case .duplicates:
                        Text("Arquivos com conteúdo idêntico. Mantenha ao menos uma cópia de cada grupo.").foregroundStyle(AppStyle.muted)
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
                                Text("Imagens visualmente semelhantes").fontWeight(.semibold)
                                fileRow(pair.first)
                                fileRow(pair.second)
                            }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                        if snapshot.skippedImages > 0 { Text("\(snapshot.skippedImages) imagens ficaram fora da comparação. Limite: 500 imagens locais de até 40 MB.").foregroundStyle(AppStyle.muted) }
                    }
                }
            }.frame(minHeight: 270, maxHeight: 400)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ByteText.format(model.selectedFiles.reduce(0) { $0 &+ $1.logicalBytes })).font(.system(size: 22, weight: .semibold))
                    Text("\(model.selectedFiles.count) arquivos selecionados").font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                }
                if !model.selectedIDs.isEmpty { Button("Desmarcar") { model.selectedIDs = [] }.buttonStyle(.plain).foregroundStyle(AppStyle.muted) }
                Spacer()
                Button("Remover…") { reviewing = true }
                    .buttonStyle(.borderedProminent).tint(.pink).controlSize(.large).disabled(model.selectedFiles.isEmpty)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.primary)
        .tint(.purple)
        .environment(\.colorScheme, .light)
    }

    private func symbol(_ category: Category) -> String {
        switch category { case .downloads: "tray.full"; case .old: "clock.arrow.circlepath"; case .duplicates: "doc.on.doc"; case .similar: "photo.on.rectangle" }
    }
    private func count(_ category: Category, snapshot: OrganizationSnapshot) -> Int {
        switch category {
        case .downloads: snapshot.downloads.count
        case .old: snapshot.oldFiles.count
        case .duplicates: snapshot.duplicateGroups.reduce(0) { $0 + $1.files.count }
        case .similar: Set(snapshot.similarImages.flatMap { [$0.first.id, $0.second.id] }).count
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
                Text(file.relativePath).font(.system(size: 11)).foregroundStyle(AppStyle.muted).lineLimit(1).truncationMode(.middle).help(file.relativePath)
                Text(file.modifiedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
            }
            Spacer()
            Text(ByteText.format(file.logicalBytes)).font(.system(size: 12, weight: .medium)).foregroundStyle(AppStyle.muted)
            Button("Abrir") { NSWorkspace.shared.open(file.url) }.buttonStyle(.plain).foregroundStyle(.purple)
            Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.buttonStyle(.plain).foregroundStyle(.purple)
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
