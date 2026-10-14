import Combine
import SwiftUI

struct ActivityEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let title: String
    let detail: String
    let symbol: String
}

@MainActor final class ActivityStore: ObservableObject {
    @Published private(set) var entries: [ActivityEntry] = []
    private let key = ScanScope.isFixture ? "activityHistory.fixture" : "activityHistory.local"
    init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([ActivityEntry].self, from: data) { entries = saved }
    }
    func record(_ title: String, detail: String, symbol: String) {
        entries.insert(ActivityEntry(title: title, detail: detail, symbol: symbol), at: 0)
        entries = Array(entries.prefix(100))
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
    func clear() { entries = []; UserDefaults.standard.removeObject(forKey: key) }
}

struct ActivityHistoryView: View {
    @ObservedObject var store: ActivityStore
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Atividades").font(.system(size: 34, weight: .regular))
                Spacer()
                if !store.entries.isEmpty { Button("Limpar histórico") { confirmClear = true }.buttonStyle(.bordered) }
            }
            Text("Histórico local de análises e operações registradas por este app.").foregroundStyle(AppStyle.muted)
            if store.entries.isEmpty {
                ContentUnavailableView("Seu histórico começa aqui", systemImage: "waveform.path", description: Text("As análises concluídas e operações registradas aparecerão nesta tela."))
                    .frame(maxWidth: .infinity, minHeight: 390)
            } else {
                ForEach(store.entries) { entry in
                    HStack(alignment: .top, spacing: 16) {
                        ModuleIcon(symbol: entry.symbol, accent: .purple, size: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title).font(.system(size: 15, weight: .semibold))
                            Text(entry.detail).font(.system(size: 12)).foregroundStyle(AppStyle.muted)
                        }
                        Spacer()
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(AppStyle.muted)
                    }.padding(18).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.padding(.top, 24)
            .confirmationDialog("Limpar o histórico de atividades?", isPresented: $confirmClear) {
                Button("Limpar histórico", role: .destructive) { store.clear() }
            } message: { Text("Isso remove apenas os registros desta tela.") }
    }
}
