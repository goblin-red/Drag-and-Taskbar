import SwiftUI

struct WindowSettingsTab: View {
    @Binding var modifier: DragModifier
    @Binding var zoom: Bool
    @Binding var exitFullscreenOnSwipeDown: Bool
    @Binding var swipeThreshold: Double
    @Binding var swipeFlick: Double
    @Binding var swipeIndicatorGain: Double
    @Binding var optionMouseDrag: Bool
    @Binding var optionSwipeHorizontal: Bool
    @Binding var optionSwipeVertical: Bool

    var body: some View {
        Form {
            Section(tr("Maximize window", "Расширить окно")) {
                Toggle(tr("Enable \(modifier.title) + double click", "Включить \(modifier.title) + двойной клик"), isOn: $zoom)
                SettingsHelpText(tr("Also in the “1 finger” mode: \(modifier.title) + two-finger swipe up maximizes the window, swipe down restores its size.", "Также в режиме «1 палец»: \(modifier.title) + свайп двумя пальцами вверх — развернуть окно, вниз — вернуть прежний размер."))
                Toggle(tr("Swipe down leaves full screen", "Свайп вниз выводит из полноэкранного режима"), isOn: $exitFullscreenOnSwipeDown)
                SettingsHelpText(tr("If the window is in native full screen (the green button / ⌃⌘F), a swipe down first takes it out of full screen. macOS animates the return to the previous window size itself.", "Если окно сейчас в нативном fullscreen (зелёная кнопка / ⌃⌘F), свайп вниз сначала выводит его из полноэкранного режима. macOS сам анимирует возврат к прежнему «оконному» размеру."))
                SettingsSliderRow(
                    title: tr("Up/down swipe threshold", "Порог свайпа вверх/вниз"),
                    value: $swipeThreshold,
                    range: 1...500,
                    step: 1,
                    valueText: tr("\(Int(swipeThreshold)) pt", "\(Int(swipeThreshold)) пт"),
                    help: tr("Lower: maximize and restore trigger from a shorter movement.", "Меньше — раскрытие и возврат срабатывают от более короткого движения.")
                )
                SettingsSliderRow(
                    title: tr("Up/down flick threshold", "Порог флика вверх/вниз"),
                    value: $swipeFlick,
                    range: 1...120,
                    step: 1,
                    valueText: "\(Int(swipeFlick))",
                    help: tr("Lower: a quick swipe up or down is caught more easily.", "Меньше — быстрый свайп вверх или вниз ловится легче.")
                )
            }

            Section(tr("Gesture indicator", "Индикатор жеста")) {
                SettingsSliderRow(
                    title: tr("Circle gain", "Усиление кружка"),
                    value: $swipeIndicatorGain,
                    range: 0.5...5.0,
                    step: 0.1,
                    valueText: String(format: "%.1f×", swipeIndicatorGain),
                    help: tr("Higher: the circle moves farther from the cursor for the same swipe.", "Больше — кружок дальше уходит от курсора при той же силе свайпа.")
                )
            }

            Section(tr("Option duplicates", "Дубли Option-свайпов")) {
                Toggle(tr("Option + mouse movement", "Option + движение мыши"), isOn: $optionMouseDrag)
                SettingsHelpText(tr("Duplicates dragging a window with the cursor in the “1 finger” mode.", "Дублирует перетаскивание окна курсором в режиме «1 палец»."))
                Toggle(tr("Option + swipe left/right", "Option + свайп влево/вправо"), isOn: $optionSwipeHorizontal)
                SettingsHelpText(tr("Duplicates the horizontal swipes of the main modifier: the left/right actions come from the “Swipes” tab.", "Дублирует горизонтальные свайпы основного модификатора: действия влево/вправо берутся из вкладки «Свайпы»."))
                Toggle(tr("Option + swipe up/down", "Option + свайп вверх/вниз"), isOn: $optionSwipeVertical)
                SettingsHelpText(tr("Duplicates the vertical swipes of the main modifier: up maximizes the window, down restores its size.", "Дублирует вертикальные свайпы основного модификатора: вверх — развернуть окно, вниз — вернуть размер."))
                if modifier == .option {
                    SettingsWarningText(tr("The main modifier is already Option: these duplicates match the regular swipes.", "Основной модификатор уже Option — эти дубли совпадают с обычными свайпами."))
                }
            }
        }
        .formStyle(.grouped)
    }
}
