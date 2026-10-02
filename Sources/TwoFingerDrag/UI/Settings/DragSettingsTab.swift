import SwiftUI

struct DragSettingsTab: View {
    @Binding var enabled: Bool
    @Binding var modifier: DragModifier
    @Binding var fingers: Int
    @Binding var sensitivity: Double
    @Binding var shiftCancelsDrag: Bool
    @AppStorage(SettingsKey.language) private var languageRaw: String = AppLanguage.en.rawValue

    var body: some View {
        Form {
            Section(tr("General", "Основное")) {
                Toggle(tr("Enabled", "Включено"), isOn: $enabled)
                Picker(tr("Modifier", "Модификатор"), selection: $modifier) {
                    ForEach(DragModifier.allCases) { mod in Text(mod.title).tag(mod) }
                }
                Picker(tr("Language", "Язык"), selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language.rawValue) }
                }
            }

            Section(tr("Drag", "Перетаскивание")) {
                Picker(tr("Gesture", "Жест"), selection: $fingers) {
                    Text(tr("1 finger (follows the cursor, 1:1)", "1 палец (за курсором, 1:1)")).tag(1)
                    Text(tr("2 fingers (trackpad gesture)", "2 пальца (жест по трекпаду)")).tag(2)
                    Text(tr("Only while the right mouse button is held", "Только при зажатой правой кнопке мыши")).tag(3)
                }
                .pickerStyle(.radioGroup)

                if fingers == 3 {
                    SettingsHelpText(
                        tr("The window follows the cursor while the modifier and the right mouse button are held. ", "Окно едет за курсором, пока зажаты модификатор и правая кнопка мыши. ")
                        + tr("The context menu does not appear; without the modifier the right click works as usual. ", "Контекстное меню при этом не появляется; без модификатора правый клик работает как обычно. ")
                        + tr("Two-finger swipes are off in this mode.", "Свайпы двумя пальцами в этом режиме выключены.")
                    )
                }

                if fingers == 2 {
                    SettingsSliderRow(
                        title: tr("Travel gain", "Усиление хода"),
                        value: $sensitivity,
                        range: 1.0...5.0,
                        step: 0.5,
                        valueText: String(format: "%.1f×", sensitivity),
                        help: tr("Higher: the window travels farther for the same finger movement.", "Больше — окно проезжает дальше при том же движении пальцев.")
                    )
                }

                Toggle(tr("Shift cancels the drag", "Shift отменяет перетаскивание"), isOn: $shiftCancelsDrag)
                    .help(tr("While Shift is held together with the modifier, the window does not move; focus keeps following the cursor, as with Control.", "Пока зажат Shift вместе с модификатором, окно не двигается; фокус продолжает следовать за курсором, как при Control."))
            }
        }
        .formStyle(.grouped)
    }
}
