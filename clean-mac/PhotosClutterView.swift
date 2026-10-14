import AppKit
import Combine
import Photos
import SwiftUI

@MainActor
final class PhotosClutterViewModel: ObservableObject {
    @Published var snapshot: PhotosClutterSnapshot?
    @Published var selected = Set<String>()
    @Published var busy = false
    @Published var message: String?
    private let engine = PhotosClutterEngine()
    private var task: Task<Void, Never>?
    var chosenItems: [LocalPhotoItem] { snapshot?.groups.flatMap(\.items).filter { selected.contains($0.id) } ?? [] }

    func scan() {
        guard !busy else { return }
        busy = true; message = nil; snapshot = nil; selected = []
        task = Task {
            defer { busy = false }
            do { snapshot = try await engine.analyze() }
            catch is CancellationError { message = "Análise cancelada." }
            catch { message = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    func toggle(_ item: LocalPhotoItem, group: LocalPhotoGroup) {
        if selected.contains(item.id) { selected.remove(item.id); return }
        guard group.items.filter({ !selected.contains($0.id) }).count > 1 else {
            message = "Mantenha pelo menos uma foto de cada grupo."; return
        }
        selected.insert(item.id)
    }
    func remove() {
        guard !busy, let snapshot, !selected.isEmpty else { return }
        let identifiers = selected; busy = true
        task = Task {
            defer { busy = false }
            do {
                let count = try await engine.delete(snapshot, selectedIDs: identifiers)
                self.snapshot = nil; selected = []
                message = "\(count) foto(s) enviada(s) para Apagados no Fotos. Elas podem ser recuperadas no prazo indicado pelo app Fotos. Analise novamente para atualizar os grupos."
            } catch { message = error.localizedDescription }
        }
    }
}

struct PhotosClutterView: View {
    @StateObject private var model = PhotosClutterViewModel()
    @State private var confirmRemoval = false
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Organizar a fototeca").font(.system(size: 36, weight: .semibold, design: .rounded))
            Text("Encontre imagens repetidas e visualmente semelhantes nas fotos disponíveis neste Mac.")
                .foregroundStyle(AppStyle.muted)
            Text("A autorização para o app Fotos será solicitada ao iniciar. Até 300 fotos recentes, 16 MB por imagem e 256 MB por análise. Recursos que exigem download do iCloud são ignorados; nenhum download é solicitado.")
                .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
            HStack(spacing: 18) {
                ActionButton(title: model.busy ? "Analisando…" : "Analisar fototeca", icon: "photo.on.rectangle.angled") { model.scan() }.disabled(model.busy || ScanScope.isFixture)
                if model.busy { ProgressView().controlSize(.small); Button("Cancelar") { model.cancel() } }
                Button("Abrir Fotos") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app")) }
            }
            if ScanScope.isFixture { Text("A fototeca real fica desativada no modo fixture.").foregroundStyle(AppStyle.muted) }
            if let message = model.message { Text(message).font(.system(size: 13)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12)) }
            if let snapshot = model.snapshot {
                HStack(spacing: 12) {
                    SummaryCard(title: "Fotos analisadas", value: "\(snapshot.examinedCount)", note: "\(ByteText.format(UInt64(snapshot.bytesRead))) lidos localmente", icon: "photo")
                    SummaryCard(title: "Grupos encontrados", value: "\(snapshot.groups.count)", note: "Revisão manual antes de remover", icon: "square.stack")
                    SummaryCard(title: "Não verificadas", value: "\(snapshot.omittedCount + snapshot.unavailableCount)", note: "Limites, ausência local ou leitura indisponível", icon: "icloud.slash")
                }
                Text("Duplicatas exatas têm os mesmos bytes da imagem original. Edições, metadados do Fotos e vídeos de Live Photos não são comparados. Semelhança usa um resumo visual (dHash) e pode agrupar imagens diferentes; confira cada miniatura e mantenha a versão desejada.")
                    .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                if snapshot.groups.isEmpty {
                    ContentUnavailableView("Nenhum grupo neste recorte", systemImage: "photo.badge.checkmark", description: Text("\(snapshot.examinedCount) imagens locais verificadas de \(snapshot.libraryCount) fotos acessíveis. Itens ignorados podem conter outras duplicatas."))
                }
                ForEach(snapshot.groups) { group in photoGroup(group) }
                if !snapshot.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Cobertura da análise").font(.system(size: 15, weight: .semibold))
                        ForEach(Array(snapshot.notes.enumerated()), id: \.offset) { _, note in Text(note).font(.system(size: 11)).foregroundStyle(AppStyle.muted).textSelection(.enabled) }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
                }
                HStack {
                    Text("\(model.selected.count) foto(s) selecionada(s)").foregroundStyle(AppStyle.muted)
                    Spacer()
                    Button("Revisar remoção…") { confirmRemoval = true }.disabled(model.selected.isEmpty || model.busy)
                }
            }
        }
        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $confirmRemoval) { removalReview }
    }

    private func photoGroup(_ group: LocalPhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(group.kind.rawValue, systemImage: group.kind == .exact ? "square.on.square" : "photo.stack")
                    .font(.system(size: 18, weight: .semibold))
                Spacer(); Text("\(group.items.count) fotos · mantenha ao menos uma").foregroundStyle(AppStyle.muted)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(group.items) { item in
                    Button { model.toggle(item, group: group) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            PhotoLocalThumbnail(identifier: item.id).frame(height: 125).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                            HStack {
                                Image(systemName: model.selected.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(AppStyle.mint)
                                Text(item.filename).lineLimit(1).truncationMode(.middle)
                            }.font(.system(size: 12, weight: .medium))
                            Text("\(item.width) × \(item.height) · \(ByteText.format(UInt64(item.bytes)))").font(.system(size: 10)).foregroundStyle(AppStyle.muted)
                            if let date = item.creationDate { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(AppStyle.muted) }
                        }.padding(10).background(Color.white.opacity(model.selected.contains(item.id) ? 0.13 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(model.busy).accessibilityLabel("Selecionar \(item.filename) para remover")
                }
            }
        }.padding(20).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var removalReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remover \(model.selected.count) foto(s)?").font(.system(size: 24, weight: .semibold))
            Text("As fotos selecionadas serão enviadas para Apagados no app Fotos. O macOS poderá solicitar outra confirmação. Se Fotos do iCloud estiver ativo, essa remoção também poderá afetar seus dispositivos sincronizados.")
                .foregroundStyle(AppStyle.muted)
            Text("Ao menos uma foto de cada grupo será mantida. A análise de semelhança é aproximada: confira as imagens antes de confirmar.")
                .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(model.chosenItems) { item in
                        HStack(spacing: 12) {
                            PhotoLocalThumbnail(identifier: item.id).frame(width: 65, height: 55).clipped()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.filename)
                                Text(item.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
                            }
                        }
                    }
                }
            }.frame(maxHeight: 270)
            HStack { Spacer(); Button("Voltar") { confirmRemoval = false }; Button("Confirmar remoção") { confirmRemoval = false; model.remove() } }
        }.padding(26).frame(width: 620).background(AppStyle.background).preferredColorScheme(.dark)
    }
}

private struct PhotoLocalThumbnail: View {
    let identifier: String
    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?
    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(AppStyle.muted) }
        }
        .onAppear { load() }
        .onDisappear { if let requestID { PHImageManager.default().cancelImageRequest(requestID) } }
    }
    private func load() {
        guard !ScanScope.isFixture, requestID == nil,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { return }
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat; options.resizeMode = .fast
        requestID = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 320, height: 240), contentMode: .aspectFit, options: options) { value, _ in
            Task { @MainActor in image = value }
        }
    }
}
