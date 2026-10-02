import SwiftUI

struct SwipeSettingsTab: View {
    @Binding var fingers: Int
    @Binding var swipes: Bool
    @Binding var swipeMethod: String
    @Binding var swipeLeftAction: WindowSwipeAction
    @Binding var swipeRightAction: WindowSwipeAction
    @Binding var swipeThreshold: Double
    @Binding var swipeFlick: Double

    var body: some View {
        Form {
            Section(tr("Two-finger swipes", "Свайпы двумя пальцами")) {
                if fingers == 1 {
                    Toggle(tr("Swipes enabled", "Свайпы включены"), isOn: $swipes)
                    if swipes {
                        SettingsHelpText(tr("◀ minimize · close ▶ · ▲ maximize · ▼ restore size", "◀ свернуть · закрыть ▶ · ▲ развернуть · ▼ вернуть размер"))
                        Picker(tr("Apply to", "Действуют на"), selection: $swipeMethod) {
                            Text(tr("Window under the cursor", "Окно под курсором")).tag("window")
                            Text(tr("Active window (⌘M / ⌘W)", "Активное окно (⌘M / ⌘W)")).tag("keys")
                        }
                        Picker(tr("Swipe left", "Свайп влево"), selection: $swipeLeftAction) {
                            ForEach(WindowSwipeAction.allCases) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        Picker(tr("Swipe right", "Свайп вправо"), selection: $swipeRightAction) {
                            ForEach(WindowSwipeAction.allCases) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        SettingsSliderRow(
                            title: tr("Swipe threshold", "Порог свайпа"),
                            value: $swipeThreshold,
                            range: 1...500,
                            step: 1,
                            valueText: tr("\(Int(swipeThreshold)) pt", "\(Int(swipeThreshold)) пт"),
                            help: tr("Lower: a slow swipe triggers sooner.", "Меньше — медленный свайп срабатывает раньше.")
                        )
                        SettingsSliderRow(
                            title: tr("Flick threshold", "Порог флика"),
                            value: $swipeFlick,
                            range: 1...120,
                            step: 1,
                            valueText: "\(Int(swipeFlick))",
                            help: tr("Lower: a quick swipe is caught more easily and faster.", "Меньше — резкий свайп ловится легче и мгновеннее.")
                        )
                    }
                } else {
                    SettingsHelpText(
                        fingers == 3
                            ? tr("Swipes are off in the “right mouse button” mode: only dragging works. Switch to the “1 finger” mode to get swipes back.", "В режиме «правая кнопка мыши» свайпы выключены — доступно только перетаскивание. Включи режим «1 палец», чтобы вернуть свайпы.")
                            : tr("Swipes work in the “1 finger” mode, where the two-finger gesture is free.", "Свайпы доступны в режиме «1 палец» — там жест двумя пальцами свободен.")
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}
