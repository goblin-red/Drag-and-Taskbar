import SwiftUI

struct FocusSettingsTab: View {
    @Binding var activateOnControl: Bool
    @Binding var activateOnModifierPress: Bool
    @Binding var activateOnModifierHover: Bool
    @Binding var activateModifier: DragModifier

    var body: some View {
        Form {
            Section(tr("Window focus", "Фокус окна")) {
                Toggle(tr("Activate the window when controlling it", "Активировать окно при управлении"), isOn: $activateOnControl)
                SettingsHelpText(tr("When on, the window under the cursor becomes active when you drag, resize, minimize, close or maximize it with GOBL(in) Drag & Taskbar.", "Если включено, окно под курсором становится активным при перетаскивании, изменении размера, сворачивании, закрытии или разворачивании через GOBL(in) Drag & Taskbar."))
                Toggle(tr("Activate on key press", "Активировать по нажатию"), isOn: $activateOnModifierPress)
                Toggle(tr("Activate on cursor movement", "Активировать при движении курсора"), isOn: $activateOnModifierHover)
                if activateOnModifierPress || activateOnModifierHover {
                    Picker(tr("Activation key", "Клавиша активации"), selection: $activateModifier) {
                        ForEach(DragModifier.allCases) { mod in Text(mod.title).tag(mod) }
                    }
                }
            }

            Section(tr("How it works", "Как работает")) {
                SettingsHelpText(tr("Just pressing the chosen modifier activates the window under the cursor, even without moving the mouse.", "Простое нажатие выбранного модификатора активирует окно под курсором даже без движения мыши."))
                SettingsHelpText(tr("Hold the chosen modifier and move the cursor: the window under it becomes active without a click.", "При движении удерживай выбранный модификатор и веди курсор: активным станет окно под курсором без клика."))
            }
        }
        .formStyle(.grouped)
    }
}
