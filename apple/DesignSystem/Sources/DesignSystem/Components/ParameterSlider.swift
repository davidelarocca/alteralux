import SwiftUI

/// A labelled slider with its value shown on the right.
///
/// Double-click resets it to its default. With the keyboard, the arrow keys
/// move a focused slider one step and Delete resets it.
public struct ParameterSlider: View {
    private let title: LocalizedStringKey
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let defaultValue: Double
    private let fractionDigits: Int
    private let showsSign: Bool

    /// - Parameters:
    ///   - step: the value snaps to multiples of this.
    ///   - defaultValue: restored by a double-click or Delete.
    ///   - fractionDigits: decimals shown in the value.
    ///   - showsSign: show `+` for positive values (for offsets around zero).
    public init(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 0.01,
        defaultValue: Double = 0,
        fractionDigits: Int = 2,
        showsSign: Bool = false,
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.fractionDigits = fractionDigits
        self.showsSign = showsSign
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                // `Text` formats with the environment's locale, so the value follows the
                // language of the view it is in.
                Text(value, format: valueFormat)
                    .font(Typography.value)
                    .foregroundStyle(.secondary)
            }
            // Stepping is done in the binding: a stepped Slider draws a tick
            // mark for every step.
            Slider(value: steppedValue, in: range) {
                Text(title)
            }
            .labelsHidden()
            .onKeyPress(.delete) {
                reset()
                return .handled
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: reset)
        .help("Double-click to reset")
        .accessibilityAction(named: "Reset", reset)
    }

    private func reset() {
        value = defaultValue
    }

    private var steppedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = ($0 / step).rounded() * step },
        )
    }

    private var valueFormat: FloatingPointFormatStyle<Double> {
        .number
            .precision(.fractionLength(fractionDigits))
            .sign(strategy: showsSign ? .always(includingZero: false) : .automatic)
    }
}

#Preview("Parameter sliders") {
    @Previewable @State var exposure = 0.3
    @Previewable @State var printExposure = 1.0
    @Previewable @State var filter = -12.0

    VStack(alignment: .leading, spacing: Spacing.l) {
        ParameterSlider("Exposure", value: $exposure, in: -5 ... 5, step: 0.1, fractionDigits: 1, showsSign: true)
        ParameterSlider("Print exposure", value: $printExposure, in: 0.2 ... 3, defaultValue: 1)
        ParameterSlider("Yellow filter", value: $filter, in: -50 ... 50, step: 1, fractionDigits: 0, showsSign: true)
        ParameterSlider(
            "A long parameter name that has to share the row with its value",
            value: $filter, in: -50 ... 50, step: 1, fractionDigits: 0,
        )
    }
    .padding(Spacing.l)
    .frame(width: 320)
}
