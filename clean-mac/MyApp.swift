import SwiftUI

@main struct MyApp: App {
    @StateObject private var health = SystemHealth()
    @AppStorage("showMenuBar") private var showMenuBar = true
    var body: some Scene {
        WindowGroup("Clean Mac", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ajustes…") { NotificationCenter.default.post(name: .cleanMacNavigate, object: "settings") }
                    .keyboardShortcut(",")
            }
            CommandMenu("Ferramentas") {
                ForEach(ContentView.Section.allCases) { section in
                    Button(section.title) {
                        NotificationCenter.default.post(name: .cleanMacNavigate, object: section.rawValue)
                    }
                }
            }
        }
        MenuBarExtra("Clean Mac", systemImage: "sparkles", isInserted: $showMenuBar) {
            HealthMenuView(health: health)
        }.menuBarExtraStyle(.window)
    }
}
