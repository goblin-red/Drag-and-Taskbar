import SwiftUI
import AppKit

struct AccessSettingsTab: View {
    @Binding var launchAtLogin: Bool
    let resetDefaults: () -> Void
    @State private var loginItemStatus = LoginItemManager.shared.statusTitle
    @State private var saveStatus = ""

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                launchAtLogin = newValue
                LoginItemManager.shared.setEnabled(newValue)
                loginItemStatus = LoginItemManager.shared.statusTitle
            }
        )
    }

    var body: some View {
        Form {
            Section(tr("Launch", "Запуск")) {
                Toggle(tr("Open the app when macOS starts", "Загружать приложение при старте macOS"), isOn: launchAtLoginBinding)
                SettingsHelpText(tr("Status in macOS: \(loginItemStatus)", "Статус в macOS: \(loginItemStatus)"))
            }

            Section(tr("Access and configuration", "Доступ и конфигурация")) {
                Button(tr("Open Accessibility settings…", "Открыть «Универсальный доступ»…")) {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                Button(tr("Save settings", "Сохранить настройки")) {
                    SettingsConfig.shared.saveNow()
                    saveStatus = tr("Saved to config.txt, default-config.txt updated.", "Сохранено в config.txt, default-config.txt обновлён.")
                }
                Button(tr("Open the config file", "Открыть файл конфигурации")) {
                    NSWorkspace.shared.open(SettingsConfig.shared.configURL)
                }
                Button(tr("Open the default-config backup", "Открыть резервный default-config")) {
                    SettingsConfig.shared.saveNow()
                    NSWorkspace.shared.open(SettingsConfig.shared.defaultConfigURL)
                }
                if !saveStatus.isEmpty {
                    SettingsHelpText(saveStatus)
                }
            }

            Section(tr("Reset", "Сброс")) {
                Button(tr("Reset settings", "Сбросить настройки")) {
                    resetDefaults()
                    saveStatus = tr("Settings reset. Press “Save settings” to write config.txt right away.", "Настройки сброшены. Нажми «Сохранить настройки», чтобы сразу записать config.txt.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginItemStatus = LoginItemManager.shared.statusTitle
        }
        .onChange(of: launchAtLogin) { newValue in
            LoginItemManager.shared.setEnabled(newValue)
            loginItemStatus = LoginItemManager.shared.statusTitle
        }
    }
}
