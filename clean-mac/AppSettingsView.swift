import AppKit
import SwiftUI

extension Notification.Name {
    static let cleanMacNavigate = Notification.Name("cleanMac.navigate")
}

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Ajustes").font(.system(size: 28, weight: .semibold))
                Spacer()
                Button("Concluído") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Toggle("Mostrar saúde do Mac na barra de menus", isOn: $showMenuBar)
            Divider()
            Label("Acesso aos arquivos", systemImage: "folder.badge.gearshape").font(.headline)
            Text("Autorize Clean Mac em Acesso Total ao Disco para analisar caches protegidos, dados do Mail, lixeiras e permissões de aplicativos. O macOS pode exigir que você reabra o app.")
                .foregroundStyle(AppStyle.muted)
            Button("Abrir Acesso Total ao Disco") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            Divider()
            Label("Processamento local", systemImage: "lock.shield").font(.headline)
            Text("As análises usam arquivos e informações deste Mac. As sugestões exigem revisão; os itens compatíveis vão para a Lixeira. Esvaziar a Lixeira e apagar versões são operações permanentes com confirmação própria.")
                .foregroundStyle(AppStyle.muted)
            Text("Clean Mac · 1.0 · macOS 15+").font(.caption).foregroundStyle(AppStyle.muted)
        }
        .font(.system(size: 13)).padding(28).frame(width: 560)
        .background(AppStyle.background).preferredColorScheme(.dark)
    }
}

struct HealthMenuView: View {
    @ObservedObject var health: SystemHealth
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(AppStyle.mint)
                Text("Clean Mac").font(.headline)
                Spacer()
                Text(health.snapshot.thermalState).font(.caption).foregroundStyle(.secondary)
            }
            metric("CPU", value: health.snapshot.cpuUsage.map { String(format: "%.0f%%", $0 * 100) } ?? "—", icon: "cpu")
            metric("Memória em uso", value: ByteText.format(health.snapshot.memoryUsed), icon: "memorychip")
            metric("Disco disponível", value: ByteText.format(health.snapshot.diskAvailable), icon: "internaldrive")
            if let battery = health.snapshot.batteryPercent { metric("Bateria", value: "\(battery)%", icon: health.snapshot.batteryCharging ? "battery.100percent.bolt" : "battery.75percent") }
            Divider()
            Button("Abrir Clean Mac") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) { window.makeKeyAndOrderFront(nil) }
                else { NSWorkspace.shared.open(Bundle.main.bundleURL) }
            }
            Button("Encerrar Clean Mac") { NSApp.terminate(nil) }
        }.padding(20).frame(width: 300).onAppear { health.start() }.onDisappear { health.stop() }
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack { Label(title, systemImage: icon); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 12))
    }
}
