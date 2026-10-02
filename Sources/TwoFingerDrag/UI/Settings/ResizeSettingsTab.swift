import SwiftUI

struct ResizeSettingsTab: View {
    @Binding var modifier: DragModifier
    @Binding var optionSwipeHorizontal: Bool
    @Binding var optionSwipeVertical: Bool
    @Binding var resizeEnabled: Bool
    @Binding var resizeModifier: DragModifier
    @Binding var resizeGain: Double
    @Binding var resizeTwoAxis: Bool
    @Binding var resizeMemorySeconds: Double

    var body: some View {
        Form {
            Section(tr("Resize with a swipe", "Изменение размера свайпом")) {
                Toggle(tr("Enabled", "Включено"), isOn: $resizeEnabled)
                if resizeEnabled {
                    Picker(tr("Resize modifier", "Модификатор размера"), selection: $resizeModifier) {
                        ForEach(DragModifier.allCases) { mod in Text(mod.title).tag(mod) }
                    }
                    if resizeModifier == modifier {
                        SettingsWarningText(tr("Same as the drag modifier: choose another one.", "Совпадает с модификатором перетаскивания — выбери другой."))
                    }
                    if resizeModifier == .option && (optionSwipeHorizontal || optionSwipeVertical) {
                        SettingsWarningText(tr("Option is used for resizing: resize takes priority over Option swipes.", "Option выбран для изменения размера — resize имеет приоритет над Option-свайпами."))
                    }
                    SettingsSliderRow(
                        title: tr("Resize speed", "Скорость изменения"),
                        value: $resizeGain,
                        range: 1.0...5.0,
                        step: 0.5,
                        valueText: String(format: "%.1f×", resizeGain)
                    )
                    Toggle(tr("Change width and height together", "Менять ширину и высоту одновременно"), isOn: $resizeTwoAxis)
                    SettingsHelpText(tr("When off, the first confident gesture locks one axis. When on, a diagonal gesture changes width and height together.", "Если выключено, первый уверенный жест фиксирует одну ось. Если включено, диагональный жест одновременно меняет ширину и высоту."))
                    SettingsSliderRow(
                        title: tr("Direction memory", "Память направления"),
                        value: $resizeMemorySeconds,
                        range: 0...10,
                        step: 0.5,
                        valueText: String(format: tr("%.1f s", "%.1f сек"), resizeMemorySeconds),
                        help: tr("During this time the next gesture on the same window and axis continues the previous swipe: the opposite direction does the reverse action.", "В течение этого времени следующий жест по тому же окну и оси продолжает логику прошлого свайпа: противоположное направление делает обратное действие.")
                    )
                }
            }

            Section(tr("Behavior", "Поведение")) {
                SettingsHelpText(tr("The window grows into the free space at the screen edges. Horizontal is width, vertical is height.", "Окно расширяется по свободному месту у краёв экрана. Горизонталь — ширина, вертикаль — высота."))
            }
        }
        .formStyle(.grouped)
    }
}
