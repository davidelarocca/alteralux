import SwiftUI

/// A labelled slider with its value shown on the right. Double-click resets
/// it to its default.
struct ParameterSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var defaultValue: Double = 0
    var fractionDigits = 2
    var showsSign = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { value = defaultValue }
        .help("Double-click to reset")
    }

    private var formattedValue: String {
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(fractionDigits))
            .sign(strategy: showsSign ? .always(includingZero: false) : .automatic)
        return value.formatted(style)
    }
}
