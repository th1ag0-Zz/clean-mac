import Combine
import SwiftUI

struct SmartCareSnapshot: Sendable {
    let cleanupCount: Int
    let cleanupBytes: UInt64
    let advancedCount: Int
    let advancedBytes: UInt64
    let duplicateGroups: Int
    let duplicateSavings: UInt64
    let largeFiles: Int
    let appResidues: Int
    let oldInstallers: Int
    let issues: Int
    let cleanupResult: AnalysisResult
    let advancedResult: AdvancedResult
    let organizationResult: OrganizationSnapshot
    let largeFilesResult: LargeFilesSnapshot
    let applicationsResult: ApplicationsSnapshot
    let protectionResult: ProtectionSnapshot?
    let protectionError: String?
}

enum SmartCareStage: Int, CaseIterable, Sendable {
    case cleanup, advanced, protection, organization, largeFiles, applications, complete
    var title: String {
        switch self {
        case .cleanup: "Procurando arquivos desnecessários"
        case .advanced: "Analisando dados do sistema"
        case .protection: "Verificando a proteção local"
        case .organization: "Encontrando arquivos repetidos"
        case .largeFiles: "Localizando arquivos grandes"
        case .applications: "Revisando aplicativos"
        case .complete: "Preparando seus resultados"
        }
    }
    var detail: String {
        switch self {
        case .cleanup: "Caches, registros e instaladores antigos"
        case .advanced: "Dados de desenvolvimento, backups e arquivos temporários"
        case .protection: "Downloads, itens de inicialização e ajustes de segurança"
        case .organization: "Comparando o conteúdo dos arquivos locais"
        case .largeFiles: "Arquivos com 100 MB ou mais nas pastas analisadas"
        case .applications: "Aplicativos instalados, resíduos e instaladores"
        case .complete: "Organizando o que você pode revisar"
        }
    }
    var progress: Double { Double(rawValue) / Double(Self.allCases.count - 1) }
}

actor SmartCareEngine {
    func scan(progress: @Sendable (SmartCareStage) async -> Void = { _ in }) async throws -> SmartCareSnapshot {
        await progress(.cleanup)
        let cleanup = try await AnalysisEngine().analyze()
        try Task.checkCancellation()
        await progress(.advanced)
        let advanced = try await AdvancedCleanupEngine().analyze()
        try Task.checkCancellation()
        await progress(.protection)
        var protection: ProtectionSnapshot?
        var protectionError: String?
        do { protection = try await ProtectionEngine().analyze() }
        catch is CancellationError { throw CancellationError() }
        catch { protectionError = error.localizedDescription }
        try Task.checkCancellation()
        await progress(.organization)
        let organization = try await OrganizationEngine().scan()
        try Task.checkCancellation()
        await progress(.largeFiles)
        let largeFiles = try await LargeFilesEngine().scan()
        try Task.checkCancellation()
        await progress(.applications)
        let apps = try await ApplicationsEngine().scan()
        try Task.checkCancellation()
        await progress(.complete)
        let cleanupBytes = cleanup.candidates.reduce(UInt64(0)) { Self.add($0, $1.logicalBytes) }
        let advancedBytes = advanced.candidates.reduce(UInt64(0)) { Self.add($0, $1.logicalBytes) }
        let duplicateSavings = organization.duplicateGroups.reduce(UInt64(0)) { Self.add($0, $1.possibleSavings) }
        return SmartCareSnapshot(cleanupCount: cleanup.candidates.count, cleanupBytes: cleanupBytes,
                                 advancedCount: advanced.candidates.count, advancedBytes: advancedBytes,
                                 duplicateGroups: organization.duplicateGroups.count,
                                 duplicateSavings: duplicateSavings, largeFiles: largeFiles.files.count,
                                 appResidues: apps.residues.count, oldInstallers: apps.installers.count,
                                 issues: cleanup.issues.count + advanced.issues.count + organization.inaccessibleLocations +
                                     largeFiles.inaccessibleLocations + apps.installerAnalysis.issues.count +
                                     (protection?.issues.count ?? 0) + (protectionError == nil ? 0 : 1),
                                 cleanupResult: cleanup, advancedResult: advanced,
                                 organizationResult: organization, largeFilesResult: largeFiles, applicationsResult: apps,
                                 protectionResult: protection, protectionError: protectionError)
    }

    private static func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let value = lhs.addingReportingOverflow(rhs)
        return value.overflow ? UInt64.max : value.partialValue
    }
}

@MainActor
final class SmartCareViewModel: ObservableObject {
    enum State { case idle, scanning, results, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: SmartCareSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var stage: SmartCareStage = .cleanup
    private let engine = SmartCareEngine()
    private var task: Task<Void, Never>?
    private var scanID = UUID()

    func scan() {
        task?.cancel()
        scanID = UUID()
        let currentID = scanID
        state = .scanning
        stage = .cleanup
        error = nil
        snapshot = nil
        task = Task {
            do {
                let result = try await engine.scan { [weak self] stage in
                    await self?.receive(stage, scanID: currentID)
                }
                try Task.checkCancellation()
                guard scanID == currentID else { return }
                snapshot = result
                state = .results
            } catch is CancellationError {
                guard scanID == currentID else { return }
                state = .idle
            } catch {
                guard scanID == currentID else { return }
                self.error = error.localizedDescription
                state = .failed
            }
        }
    }

    private func receive(_ stage: SmartCareStage, scanID: UUID) {
        guard self.scanID == scanID, state == .scanning else { return }
        self.stage = stage
    }

    func cancel() {
        task?.cancel()
        scanID = UUID()
        state = .idle
    }
}

#if !SMARTCARE_TESTING
struct SmartCareView: View {
    @ObservedObject var model: SmartCareViewModel
    @StateObject private var health = SystemHealth()
    let openCleanup: () -> Void
    let openAdvanced: () -> Void
    let openOrganization: () -> Void
    let openLargeFiles: () -> Void
    let openApplications: () -> Void
    let openPerformance: () -> Void
    var openProtection: () -> Void = {}

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                ModuleLandingView(title: "Cuidados\nInteligentes",
                                  subtitle: "Um Mac mais limpo, organizado e pronto para o seu dia.",
                                  symbol: "desktopcomputer", accent: .pink,
                                  features: [("sparkles", "Encontre espaço para liberar"),
                                             ("shield.lefthalf.filled", "Revise a proteção do seu Mac"),
                                             ("square.grid.2x2", "Organize arquivos e aplicativos")]) { model.scan() }
            case .scanning:
                VStack(spacing: 18) {
                    ScanOrbitView(title: model.stage.title, detail: model.stage.detail,
                                  progress: model.stage.progress) { model.cancel() }
                    HStack(spacing: 8) {
                        ForEach(SmartCareStage.allCases.filter { $0 != .complete }, id: \.rawValue) { stage in
                            Capsule().fill(stage.rawValue <= model.stage.rawValue ? Color.pink : Color.white.opacity(0.15))
                                .frame(width: 28, height: 4)
                        }
                    }.accessibilityLabel("Etapa \(min(model.stage.rawValue + 1, 6)) de 6")
                    Text("Você poderá revisar os resultados antes de fazer alterações.")
                        .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                }
            case .failed:
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 48)).foregroundStyle(.orange)
                    Text("A análise foi interrompida").font(.system(size: 26, weight: .semibold))
                    Text(model.error ?? "Não foi possível concluir a análise.").foregroundStyle(AppStyle.muted)
                    ActionButton(title: "Tentar novamente", icon: "arrow.clockwise") { model.scan() }
                }.frame(maxWidth: .infinity, minHeight: 400)
            case .results:
                if let snapshot = model.snapshot { results(snapshot) }
            }
        }
        .onAppear { health.start() }
        .onDisappear { health.stop() }
    }

    private func results(_ result: SmartCareSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Análise concluída").font(.system(size: 28, weight: .semibold))
                    Text("Veja o que merece sua atenção.").font(.system(size: 13)).foregroundStyle(AppStyle.muted)
                }
                Spacer()
                Button("Analisar novamente") { model.scan() }.buttonStyle(.bordered)
            }.padding(.bottom, 4)
            if result.issues > 0 {
                Label("\(count(result.issues, "aviso", "avisos")) de acesso ou cobertura · detalhes em cada área", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                resultCard("Limpeza", icon: "sparkles", color: .green,
                           detail: "\(ByteText.format(result.cleanupBytes)) em \(count(result.cleanupCount, "item", "itens"))",
                           action: openCleanup) {
                    Button("Dados adicionais · \(ByteText.format(result.advancedBytes))") { openAdvanced() }
                }
                resultCard("Proteção", icon: "hand.raised.fill", color: .pink,
                           detail: protectionDetail(result), action: openProtection) {
                    Text("Auditoria local · cobertura limitada").foregroundStyle(AppStyle.muted)
                }
                resultCard("Desempenho", icon: "speedometer", color: .orange,
                           detail: "\(ByteText.format(health.snapshot.memoryUsed)) de \(ByteText.format(health.snapshot.memoryTotal)) de memória em uso",
                           action: openPerformance) {
                    Text("Condição térmica: \(health.snapshot.thermalState)").foregroundStyle(AppStyle.muted)
                }
                resultCard("Aplicativos", icon: "square.grid.2x2.fill", color: .blue,
                           detail: "\(count(result.applicationsResult.apps.count, "aplicativo", "aplicativos")) · \(count(result.appResidues, "possível resíduo", "possíveis resíduos"))",
                           action: openApplications) {
                    Text(count(result.oldInstallers, "instalador antigo", "instaladores antigos")).foregroundStyle(AppStyle.muted)
                }
                resultCard("Acúmulos", icon: "square.stack.3d.up.fill", color: .teal,
                           detail: "\(count(result.duplicateGroups, "grupo de duplicatas", "grupos de duplicatas")) · até \(ByteText.format(result.duplicateSavings)) em cópias",
                           action: openOrganization) {
                    Button("Revisar \(count(result.largeFiles, "arquivo grande", "arquivos grandes"))") { openLargeFiles() }
                }
            }
            Text("As estimativas de espaço podem se sobrepor. Revise os itens antes de confirmar a ação.")
                .font(.system(size: 10)).foregroundStyle(AppStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    private func protectionDetail(_ result: SmartCareSnapshot) -> String {
        guard let protection = result.protectionResult else {
            return "Auditoria indisponível. Abra Proteção para tentar novamente."
        }
        let attention = (protection.findings + protection.security).filter(\.attention).count
        return "\(count(attention, "observação", "observações")) · \(count(protection.scannedFiles, "arquivo verificado", "arquivos verificados"))"
    }

    private func resultCard<Detail: View>(_ title: String, icon: String, color: Color,
                                         detail: String, action: @escaping () -> Void,
                                         @ViewBuilder secondary: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color).frame(width: 34, height: 34)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                Button("Revisar", action: action).buttonStyle(.bordered).controlSize(.small)
            }
            Text(detail).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            secondary().font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(0.13), lineWidth: 1))
    }

}

#endif
