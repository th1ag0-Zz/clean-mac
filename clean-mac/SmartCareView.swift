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
}

actor SmartCareEngine {
    func scan() async throws -> SmartCareSnapshot {
        let cleanup = try await AnalysisEngine().analyze()
        try Task.checkCancellation()
        let advanced = try await AdvancedCleanupEngine().analyze()
        try Task.checkCancellation()
        let organization = try await OrganizationEngine().scan()
        try Task.checkCancellation()
        let largeFiles = try await LargeFilesEngine().scan()
        try Task.checkCancellation()
        let apps = try await ApplicationsEngine().scan()
        let cleanupBytes = cleanup.candidates.reduce(UInt64(0)) { Self.add($0, $1.logicalBytes) }
        let advancedBytes = advanced.candidates.reduce(UInt64(0)) { Self.add($0, $1.logicalBytes) }
        let duplicateSavings = organization.duplicateGroups.reduce(UInt64(0)) { Self.add($0, $1.possibleSavings) }
        return SmartCareSnapshot(cleanupCount: cleanup.candidates.count, cleanupBytes: cleanupBytes,
                                 advancedCount: advanced.candidates.count, advancedBytes: advancedBytes,
                                 duplicateGroups: organization.duplicateGroups.count,
                                 duplicateSavings: duplicateSavings, largeFiles: largeFiles.files.count,
                                 appResidues: apps.residues.count, oldInstallers: apps.installers.count,
                                 issues: advanced.issues.count + organization.inaccessibleLocations +
                                     largeFiles.inaccessibleLocations,
                                 cleanupResult: cleanup, advancedResult: advanced,
                                 organizationResult: organization, largeFilesResult: largeFiles, applicationsResult: apps)
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
    private let engine = SmartCareEngine()
    private var task: Task<Void, Never>?
    private var scanID = UUID()

    func scan() {
        task?.cancel()
        scanID = UUID()
        let currentID = scanID
        state = .scanning
        error = nil
        snapshot = nil
        task = Task {
            do {
                let result = try await engine.scan()
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

    func cancel() {
        task?.cancel()
        scanID = UUID()
        state = .idle
    }
}

struct SmartCareView: View {
    @ObservedObject var model: SmartCareViewModel
    let openCleanup: () -> Void
    let openAdvanced: () -> Void
    let openOrganization: () -> Void
    let openLargeFiles: () -> Void
    let openApplications: () -> Void
    let openPerformance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Cuidados Inteligentes")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Uma análise local de limpeza, arquivos repetidos, arquivos grandes e dados de aplicativos. Revise cada área antes de agir.")
                .font(.system(size: 14)).foregroundStyle(AppStyle.muted)
            switch model.state {
            case .idle:
                welcome
            case .scanning:
                ProgressView("Analisando as áreas locais…").tint(AppStyle.mint)
                Button("Cancelar") { model.cancel() }.buttonStyle(.plain).foregroundStyle(AppStyle.mint)
            case .failed:
                Text(model.error ?? "Não foi possível concluir a análise.").foregroundStyle(.orange)
                ActionButton(title: "Tentar novamente", icon: "arrow.clockwise") { model.scan() }
            case .results:
                if let snapshot = model.snapshot { results(snapshot) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(AppStyle.aqua.opacity(0.18)).frame(width: 280, height: 280).blur(radius: 40)
                CleanerArtwork().frame(width: 300, height: 300)
                Image(systemName: "sparkle").font(.system(size: 34)).foregroundStyle(.white.opacity(0.9)).offset(x: 135, y: -90)
                Image(systemName: "sparkle").font(.system(size: 18)).foregroundStyle(AppStyle.mint).offset(x: -140, y: 20)
            }.accessibilityHidden(true)
            Text("Seu Mac merece esse cuidado.")
                .font(.system(size: 30, weight: .medium, design: .rounded)).tracking(-0.7)
            Text("Encontre espaço para o que vem a seguir.")
                .font(.system(size: 15)).foregroundStyle(AppStyle.muted)
            ActionButton(title: "Analisar", icon: "sparkle.magnifyingglass") { model.scan() }
                .accessibilityIdentifier("smartCare.scan").padding(.top, 6)
            HStack(spacing: 28) {
                Label("Limpeza", systemImage: "sparkles")
                Label("Organização", systemImage: "square.stack.3d.up")
                Label("Aplicativos", systemImage: "square.grid.2x2")
            }.font(.system(size: 12)).foregroundStyle(AppStyle.muted).padding(.top, 10)
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    private func results(_ result: SmartCareSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Análise concluída").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Reanalisar") { model.scan() }.buttonStyle(.plain).foregroundStyle(AppStyle.mint)
            }
            if result.issues > 0 {
                Text("\(result.issues) locais não puderam ser analisados completamente.")
                    .foregroundStyle(.orange)
            }
            card("Limpeza", detail: "\(result.cleanupCount) itens · \(ByteText.format(result.cleanupBytes)) estimados",
                 icon: "sparkles", action: openCleanup)
            card("Limpeza adicional", detail: "\(result.advancedCount) itens · \(ByteText.format(result.advancedBytes)) estimados",
                 icon: "square.grid.3x3", action: openAdvanced)
            card("Acúmulos", detail: "\(result.duplicateGroups) grupos de duplicatas · até \(ByteText.format(result.duplicateSavings)) em cópias",
                 icon: "square.on.square", action: openOrganization)
            card("Arquivos grandes", detail: "\(result.largeFiles) arquivos com 100 MB ou mais",
                 icon: "doc.zipper", action: openLargeFiles)
            card("Aplicativos", detail: "\(result.appResidues) resíduos · \(result.oldInstallers) instaladores antigos",
                 icon: "square.grid.2x2", action: openApplications)
            card("Desempenho", detail: "Revise apps em execução e tarefas de manutenção",
                 icon: "speedometer", action: openPerformance)
            Text("Os valores são estimativas independentes e podem se sobrepor. Nenhum arquivo foi removido pela análise.")
                .font(.system(size: 12)).foregroundStyle(AppStyle.muted)
        }
    }

    private func card(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 23)).frame(width: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppStyle.mint)
            }
            .padding(18).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
