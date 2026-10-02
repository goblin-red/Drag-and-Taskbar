import SwiftUI
import AppKit

struct MenuView: View {
    @AppStorage(SettingsKey.enabled) private var enabled: Bool = true
    @AppStorage(SettingsKey.language) private var languageRaw: String = AppLanguage.en.rawValue
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BrandLogo().frame(height: 22)
                Text("GOBL(in) Drag & Taskbar").font(.headline)
                Spacer()
            }

            Toggle(tr("Enabled", "Включено"), isOn: $enabled)

            Divider()

            Button(tr("Settings…", "Настройки…")) {
                NSApp.keyWindow?.close()
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button(tr("Quit", "Выйти")) {
                NSApp.terminate(nil)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Build: \(BuildInfo.date)", "Сборка: \(BuildInfo.date)"))
                Text(tr("Architecture: \(BuildInfo.arch)", "Архитектура: \(BuildInfo.arch)"))
                Text(tr("Thread: \(DragController.tapThreadID)", "Поток: \(DragController.tapThreadID)"))
                Text("PID: \(ProcessInfo.processInfo.processIdentifier)")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        // при смене языка меню перерисовывается целиком
        .id(languageRaw)
    }
}
