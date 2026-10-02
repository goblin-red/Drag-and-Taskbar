import SwiftUI

enum SettingsLayout {
    static let windowWidth: CGFloat = 900
    static let windowHeight: CGFloat = 680
}

struct SettingsHelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

struct SettingsWarningText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.orange)
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    let help: String?

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        help: String? = nil
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.help = help
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(title): \(valueText)")
            Slider(value: $value, in: range, step: step)
            if let help = help {
                SettingsHelpText(help)
            }
        }
    }
}
