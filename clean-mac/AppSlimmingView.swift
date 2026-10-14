import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppSlimmingViewModel: ObservableObject {
    enum State { case idle, scanning, ready, creating, finished, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: AppSlimmingSnapshot?
    @Published private(set) var result: AppSlimmingResult?
    @Published private(set) var error: String?
    @Published private(set) var outputFolder: URL?
    @Published var omittedLanguages: Set<String> = []
    @Published var thinArchitectures = false
    private let engine = AppSlimmingEngine()
    private var sourceAccess: URL?
    private var outputAccess: URL?

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = "Escolha um app local. A otimização criará uma cópia e preservará o original."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourceAccess?.stopAccessingSecurityScopedResource()
        sourceAccess = url.startAccessingSecurityScopedResource() ? url : nil
        snapshot = nil; result = nil; error = nil; omittedLanguages = []; thinArchitectures = false
        state = .scanning
        Task {
            do { snapshot = try await engine.scan(url); state = .ready }
            catch { self.error = error.localizedDescription; state = .failed }
        }
    }
    func chooseDestination() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Escolha onde salvar a cópia otimizada. Reserve espaço para uma cópia completa do app."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        releaseOutputAccess()
        outputAccess = url.startAccessingSecurityScopedResource() ? url : nil
        outputFolder = url
        return true
    }
    func releaseOutputAccess() { outputAccess?.stopAccessingSecurityScopedResource(); outputAccess = nil }
    func createCopy() {
        guard let snapshot, let outputFolder, state == .ready || state == .finished else { return }
        let languages = omittedLanguages
        let thin = thinArchitectures
        error = nil; result = nil; state = .creating
        Task {
            do {
                result = try await engine.createCopy(snapshot, omitting: languages, thinArchitectures: thin, outputFolder: outputFolder)
                state = .finished
            } catch { self.error = error.localizedDescription; state = .ready }
            releaseOutputAccess()
        }
    }
}

struct AppSlimmingView: View {
    @StateObject private var model = AppSlimmingViewModel()
    @State private var reviewing = false
    private var hasChanges: Bool { !model.omittedLanguages.isEmpty || model.thinArchitectures }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Otimizar apps").font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Crie uma cópia menor removendo idiomas dispensáveis e arquiteturas que este Mac não usa.")
                .foregroundStyle(AppStyle.muted)
            switch model.state {
            case .idle:
                ActionButton(title: "Escolher aplicativo", icon: "app.badge") { model.chooseApp() }
            case .scanning:
                ProgressView("Medindo recursos de idioma e inspecionando binários…").tint(AppStyle.mint)
            case .failed:
                Text(model.error ?? "Não foi possível inspecionar o app.").foregroundStyle(.orange).textSelection(.enabled)
                Button("Escolher outro app") { model.chooseApp() }
            case .ready, .creating, .finished:
                if let snapshot = model.snapshot { inventory(snapshot) }
            }
        }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $reviewing, onDismiss: { if model.state != .creating { model.releaseOutputAccess() } }) {
                if let snapshot = model.snapshot { review(snapshot) }
            }
    }

    private func inventory(_ snapshot: AppSlimmingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: snapshot.source.path)).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.source.lastPathComponent).font(.system(size: 20, weight: .semibold))
                    Text("\(ByteText.format(snapshot.logicalBytes)) · \(snapshot.scannedFiles) arquivos · Mac \(snapshot.nativeArchitecture)").foregroundStyle(AppStyle.muted)
                    Text(snapshot.source.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppStyle.muted).textSelection(.enabled)
                }
                Spacer()
                Button("Trocar app") { model.chooseApp() }.disabled(model.state == .creating)
            }.padding(18).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 16))
            if let error = model.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let result = model.result {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cópia otimizada criada").font(.system(size: 18, weight: .semibold)).foregroundStyle(AppStyle.mint)
                    Text("\(ByteText.format(result.beforeBytes)) → \(ByteText.format(result.afterBytes)) · redução medida: \(ByteText.format(result.savedBytes))")
                    Text("\(result.removedLanguageCount) idiomas omitidos · \(result.thinnedBinaryCount) binários reduzidos. Tamanhos lógicos; o espaço físico pode variar.").foregroundStyle(AppStyle.muted)
                    Text(result.copyURL.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Button("Mostrar cópia no Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.copyURL]) }
                    Text("Teste a cópia antes de usá-la no lugar do original.").foregroundStyle(AppStyle.muted)
                }.padding(16).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Idiomas").font(.system(size: 22, weight: .semibold))
            Text("Marque os idiomas que deseja omitir da cópia. Base, inglês, idiomas preferidos do macOS e idiomas de desenvolvimento são preservados.").foregroundStyle(AppStyle.muted)
            if snapshot.languages.isEmpty { Text("Nenhuma pasta de idioma .lproj foi encontrada.").foregroundStyle(AppStyle.muted) }
            LazyVStack(spacing: 6) {
                ForEach(snapshot.languages) { language in
                    HStack {
                        Toggle("Omitir \(language.displayName)", isOn: Binding(get: { model.omittedLanguages.contains(language.code) }, set: {
                            if $0 && !language.mustKeep { model.omittedLanguages.insert(language.code) } else { model.omittedLanguages.remove(language.code) }
                        })).labelsHidden().toggleStyle(.checkbox).disabled(language.mustKeep || model.state == .creating)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(language.displayName) (\(language.code))").fontWeight(.medium)
                            Text(language.mustKeep ? "Preservado" : "\(language.paths.count) pasta(s) de recursos").font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                        }
                        Spacer()
                        Text(ByteText.format(language.logicalBytes)).font(.system(size: 12, design: .monospaced))
                    }.padding(12).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("Arquiteturas universais").font(.system(size: 22, weight: .semibold))
            Toggle("Manter somente \(snapshot.nativeArchitecture) nos binários compatíveis", isOn: $model.thinArchitectures)
                .toggleStyle(.checkbox).disabled(snapshot.universalBinaries.isEmpty || model.state == .creating)
            Text("\(snapshot.universalBinaries.count) binários podem ser reduzidos. Binários sem arquitetura nativa são preservados. A redução exata será medida depois da cópia.").foregroundStyle(AppStyle.muted)
            ForEach(snapshot.universalBinaries) { binary in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(binary.relativePath).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Text(binary.architectures.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                    }
                    Spacer()
                    Text(ByteText.format(binary.logicalBytes)).font(.system(size: 12, design: .monospaced))
                }.padding(10).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(Array(snapshot.notes.enumerated()), id: \.offset) { _, note in Text(note).font(.system(size: 11)).foregroundStyle(.orange) }
            if model.state == .creating {
                ProgressView("Criando, otimizando e assinando a cópia…").tint(AppStyle.mint)
                Text("A operação pode levar alguns minutos. O original permanece na pasta de origem.").foregroundStyle(AppStyle.muted)
            } else {
                ActionButton(title: "Escolher destino e revisar", icon: "doc.on.doc") { if model.chooseDestination() { reviewing = true } }
                    .disabled(!hasChanges)
            }
        }
    }

    private func review(_ snapshot: AppSlimmingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Revisar cópia otimizada").font(.system(size: 25, weight: .semibold))
            Text("Origem: \(snapshot.source.path)").textSelection(.enabled)
            Text("Destino: \(model.outputFolder?.path ?? "")").textSelection(.enabled)
            Text("\(model.omittedLanguages.count) idiomas serão omitidos. \(model.thinArchitectures ? snapshot.universalBinaries.count : 0) binários serão reduzidos para \(snapshot.nativeArchitecture).")
            if !model.omittedLanguages.isEmpty { Text(model.omittedLanguages.sorted().joined(separator: ", ")).foregroundStyle(AppStyle.muted) }
            Text("A cópia receberá uma assinatura ad hoc local. A alteração pode afetar atualizações, acesso ao Chaves (Keychain), permissões e entitlements. Alguns apps podem recusar iniciar. Teste a cópia antes de substituir qualquer instalação.")
                .foregroundStyle(.orange)
            Text("O original será preservado. Não há promessa de economia em recursos protegidos. Reserve espaço para copiar o app completo; o tamanho final será medido após a assinatura.").foregroundStyle(AppStyle.muted)
            Spacer()
            HStack {
                Spacer()
                Button("Cancelar") { reviewing = false }
                Button("Confirmar e criar cópia") { model.createCopy(); reviewing = false }
            }
        }.padding(28).frame(width: 650, height: 480).background(AppStyle.background).preferredColorScheme(.dark)
    }
}
