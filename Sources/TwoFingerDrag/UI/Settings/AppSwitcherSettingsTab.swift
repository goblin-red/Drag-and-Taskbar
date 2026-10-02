import SwiftUI

struct AppSwitcherSettingsTab: View {
    @Binding var appSwitcherEnabled: Bool
    @Binding var appSwitcherModifier: DragModifier
    @Binding var appSwitcherMode: AppSwitcherMode

    var body: some View {
        Form {
            Section(tr("Taskbar", "Таск-панель")) {
                Toggle(tr("Enable the switcher", "Включить переключатель"), isOn: $appSwitcherEnabled)
                if appSwitcherEnabled {
                    Picker(tr("Modifier", "Модификатор"), selection: $appSwitcherModifier) {
                        ForEach(DragModifier.allCases) { mod in Text(mod.title).tag(mod) }
                    }
                    Picker(tr("Panel view", "Вид панели"), selection: $appSwitcherMode) {
                        ForEach(AppSwitcherMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                }
            }

            Section(tr("Modes", "Режимы")) {
                SettingsHelpText(tr("The compact view shows the visible apps of the current desktop.", "Сокращённый вид показывает видимые приложения текущего рабочего стола."))
                SettingsHelpText(tr("The extended view shows individual windows of running apps, including windows minimized to the Dock.", "Расширенный вид показывает отдельные окна запущенных приложений, включая свернутые окна из Dock."))
                SettingsHelpText(tr("\(appSwitcherModifier.title) + Tab selects the next item; releasing the modifier activates the selection.", "\(appSwitcherModifier.title) + Tab выбирает следующий элемент, отпускание модификатора активирует выбранное."))
            }
        }
        .formStyle(.grouped)
    }
}
