import AppKit
import Combine
import SwiftUI

@MainActor
final class SpaceLensViewModel: ObservableObject {
    enum State { case idle, scanning, results, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: SpaceLensSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var locationRejected = false
    @Published private(set) var removalMessage: String?
    @Published private(set) var isRemoving = false
    @Published private(set) var selectedRoot: URL?
    private let engine = SpaceLensEngine()
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()
    private var scopedURL: URL?

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Escolha uma pasta local. Pastas do sistema, links, pacotes e nuvem são ignorados."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanTask?.cancel()
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        selectedRoot = url
        scan()
    }
    func usePersonalFolders() {
        scanTask?.cancel()
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil; selectedRoot = nil
        scan()
    }
    func scan() {
        scanTask?.cancel(); scanID = UUID()
        let currentID = scanID
        let root = selectedRoot
        state = .scanning; snapshot = nil; error = nil; locationRejected = false
        scanTask = Task {
            do {
                let result = try await engine.scan(root: root)
                try Task.checkCancellation()
                guard scanID == currentID else { return }
                snapshot = result; state = .results
            } catch is CancellationError {
                guard scanID == currentID else { return }; state = .idle
            } catch {
                guard scanID == currentID else { return }
                if let fileError = error as? PersonalFileError, case .unsafeLocation = fileError {
                    locationRejected = true
                    self.error = "O Clean Mac não mapeia esta pasta. Links, pacotes, arquivos de nuvem e pastas do sistema ficam fora da Lupa de Espaço. Acesso Total ao Disco não altera esse limite."
                } else {
                    self.error = error.localizedDescription
                }
                state = .failed
            }
        }
    }
    func cancel() {
        scanTask?.cancel()
        scanID = UUID()
        state = .idle
    }
    func remove(_ item: SpaceLensItem) {
        guard !isRemoving else { return }
        isRemoving = true; removalMessage = nil
        Task {
            do {
                try await engine.moveToTrash(item)
                removalMessage = "\(item.name) foi movido para a Lixeira. Esvazie-a para liberar espaço."
                isRemoving = false; scan()
            } catch { removalMessage = error.localizedDescription; isRemoving = false }
        }
    }
}

struct SpaceLensView: View {
    @ObservedObject var model: SpaceLensViewModel
    @State private var path: [String] = []
    @State private var pendingRemoval: SpaceLensItem?
    @State private var reviewing = false
    @State private var search = ""

    @State private var showMap = true
    private let accent = Color(red: 0.73, green: 0.51, blue: 0.95)

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                VStack(spacing: 8) {
                    ModuleLandingView(title: "Lupa de Espaço",
                        subtitle: "Veja o que ocupa espaço no Mac. Explore suas pastas, encontre arquivos grandes e abra espaço para coisas novas.",
                        symbol: "magnifyingglass", accent: accent,
                        features: [("square.grid.2x2.fill", "Mapa visual"), ("folder.fill", "Pastas grandes"), ("doc.fill", "Arquivos locais")],
                        action: { path = []; model.scan() })
                    Button("Escolher outra pasta…") { path = []; model.chooseFolder() }
                        .buttonStyle(.plain).foregroundStyle(accent)
                    if let root = model.selectedRoot {
                        Text(root.path).font(.caption).foregroundStyle(AppStyle.muted)
                        Button("Analisar pastas pessoais") { path = []; model.usePersonalFolders() }
                    }
                }
            case .scanning:
                ScanOrbitView(title: "Mapeando seu espaço", detail: model.selectedRoot?.path ?? "Calculando o tamanho das pastas pessoais…", progress: nil, cancel: model.cancel)
            case .failed:
                ContentUnavailableView {
                    Label("Não foi possível mapear esta pasta", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.error ?? "A análise falhou.")
                    if let root = model.selectedRoot { Text(root.path).font(.caption) }
                } actions: {
                    if !model.locationRejected { Button("Tentar novamente") { model.scan() } }
                    Button("Escolher pasta…") { path = []; model.chooseFolder() }
                    if model.selectedRoot != nil { Button("Analisar pastas pessoais") { path = []; model.usePersonalFolders() } }
                    Button("Voltar", action: model.cancel)
                }.frame(minHeight: 500)
            case .results:
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Lupa de Espaço").font(.system(size: 32, weight: .bold))
                            Text("Explore o que ocupa espaço no seu Mac.").foregroundStyle(AppStyle.muted)
                        }
                        Spacer()
                        Button("Escolher pasta…") { path = []; model.chooseFolder() }
                        if model.selectedRoot != nil { Button("Pastas pessoais") { path = []; model.usePersonalFolders() } }
                    }
                    if let message = model.removalMessage { Text(message).foregroundStyle(accent) }
                    if let snapshot = model.snapshot { results(snapshot) }
                }
            }
        }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            .tint(accent)
            .disabled(model.isRemoving)
            .sheet(isPresented: $reviewing) {
                if let item = pendingRemoval, let identity = item.identity {
                    PersonalFileReviewSheet(files: [PersonalFileSelection(url: item.url, logicalBytes: item.logicalBytes, identity: identity)]) { model.remove(item) }
                }
            }
    }

    private func results(_ snapshot: SpaceLensSnapshot) -> some View {
        let current = selectedItem(in: snapshot)
        let items = current?.children ?? snapshot.roots
        let total = items.reduce(UInt64(0)) { partial, item in
            let sum = partial.addingReportingOverflow(item.logicalBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
        let filtered = items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(ByteText.format(total)) · \(snapshot.scannedFiles) arquivos analisados").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Analisar novamente") { path = []; model.scan() }.buttonStyle(.plain).foregroundStyle(accent)
            }
            if snapshot.truncated { Text("A análise atingiu 200.000 entradas. Os tamanhos exibidos estão incompletos.").foregroundStyle(.orange) }
            if snapshot.inaccessibleLocations > 0 { Text("\(snapshot.inaccessibleLocations) locais não puderam ser lidos.").foregroundStyle(.orange) }
            Text("Tamanhos lógicos; clones APFS podem compartilhar espaço. Itens ocultos, links, pacotes, nuvem e outros volumes ficam fora. Pastas vazias não ocupam área no mapa.")
                .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { path = []; search = "" } label: { Image(systemName: "house.fill") }.buttonStyle(.plain).help("Início")
                        ForEach(Array(path.enumerated()), id: \.offset) { index, name in
                            Image(systemName: "chevron.right").font(.system(size: 9))
                            Button(name) { path = Array(path.prefix(index + 1)); search = "" }.buttonStyle(.plain).lineLimit(1)
                        }
                    }.foregroundStyle(accent).font(.system(size: 12, weight: .semibold))
                }
                if !path.isEmpty {
                    Button { path.removeLast(); search = "" } label: { Image(systemName: "arrow.up") }.help("Pasta anterior")
                }
                Picker("Visualização", selection: $showMap) {
                    Text("Mapa").tag(true)
                    Text("Lista").tag(false)
                }.pickerStyle(.segmented).frame(width: 145)
            }
            if showMap {
                SpaceTreemap(items: items) { item in
                    if item.isDirectory { path.append(item.name); search = "" }
                    else { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                }.frame(height: 330)
            }
            TextField("Filtrar itens desta pasta", text: $search).textFieldStyle(.roundedBorder)
            if filtered.isEmpty { Text("Nenhum item corresponde ao filtro.").foregroundStyle(AppStyle.muted) }
            LazyVStack(spacing: 8) {
                ForEach(filtered) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill").foregroundStyle(accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).fontWeight(.semibold).lineLimit(1)
                            Text(item.isDirectory ? "\(item.fileCount) arquivos" : item.url.path).font(.system(size: 11)).foregroundStyle(AppStyle.muted).lineLimit(1)
                        }
                        Spacer()
                        Text(ByteText.format(item.logicalBytes)).font(.system(size: 12, design: .monospaced))
                        if item.isDirectory {
                            Button("Abrir") { path.append(item.name); search = "" }.buttonStyle(.plain).foregroundStyle(accent)
                        } else {
                            Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }.buttonStyle(.plain).foregroundStyle(accent)
                            Button { pendingRemoval = item; reviewing = true } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).accessibilityLabel("Mover \(item.name) para a Lixeira")
                        }
                    }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    private func selectedItem(in snapshot: SpaceLensSnapshot) -> SpaceLensItem? {
        var items = snapshot.roots
        var selected: SpaceLensItem?
        for component in path {
            guard let item = items.first(where: { $0.name == component }) else { return nil }
            selected = item; items = item.children
        }
        return selected
    }
}

private struct SpaceTreemap: View {
    let items: [SpaceLensItem]
    let onSelect: (SpaceLensItem) -> Void
    private let colors: [Color] = [Color(red: 0.15, green: 0.57, blue: 0.49), Color(red: 0.16, green: 0.42, blue: 0.59), Color(red: 0.43, green: 0.35, blue: 0.66), Color(red: 0.60, green: 0.38, blue: 0.38), Color(red: 0.53, green: 0.48, blue: 0.21)]

    var body: some View {
        let nonempty = items.filter { $0.logicalBytes > 0 }
        let visible = Array(nonempty.prefix(60))
        let remainder = nonempty.dropFirst(60).reduce(0.0) { $0 + Double($1.logicalBytes) }
        let weights = visible.map { Double($0.logicalBytes) } + (remainder > 0 ? [remainder] : [])
        GeometryReader { geometry in
            let frames = SpaceTreemapLayout.frames(weights: weights, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                if nonempty.isEmpty { Text("Nenhum arquivo com conteúdo nesta pasta.").foregroundStyle(AppStyle.muted).frame(width: geometry.size.width, height: geometry.size.height) }
                ForEach(Array(frames.enumerated()), id: \.offset) { index, rect in
                    let item = index < visible.count ? visible[index] : nil
                    Button { if let item { onSelect(item) } } label: {
                        ZStack {
                            Rectangle().fill(colors[index % colors.count])
                            Rectangle().strokeBorder(AppStyle.background.opacity(0.6), lineWidth: 1)
                            if rect.width > 65 && rect.height > 42 {
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(item?.name ?? "Outros \(nonempty.count - visible.count) itens", systemImage: item?.isDirectory == true ? "folder.fill" : "doc.fill")
                                        .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                    Text(ByteText.format(item?.logicalBytes ?? UInt64(min(remainder, Double(Int64.max))))).font(.system(size: 11)).lineLimit(1)
                                }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }.foregroundStyle(.white).frame(width: rect.width, height: rect.height).clipped()
                    }.buttonStyle(.plain).position(x: rect.midX, y: rect.midY)
                        .help(item.map { "\($0.name) · \(ByteText.format($0.logicalBytes))" } ?? "Os demais itens estão na lista abaixo")
                        .accessibilityLabel(item?.name ?? "Outros itens")
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
