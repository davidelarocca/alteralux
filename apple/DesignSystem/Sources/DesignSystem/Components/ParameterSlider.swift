import SwiftUI

/// A labelled slider with its value shown on the right.
///
/// The slider is the system's. It fills from the default value to the current one, in either
/// direction, so the neutral point of a parameter and how far it has been moved are both in
/// view. At the default the value is dimmed.
///
/// Double-click resets it to its default. Where sliders take the keyboard focus
/// (`slidersTakeKeyboardFocus`: the app follows the system's "Keyboard navigation"
/// setting) the arrow keys move it one step and Delete resets it. Elsewhere a click
/// leaves the keys where they were and draws no focus ring: it is moved with the pointer.
///
/// Disabled, its title and value are dimmed: the system's slider alone looks the same disabled.
///
/// A parameter that can be switched off (grain, halation) passes `isOn`: its switch sits on the
/// slider's row, and Space flips it. Off, the slider keeps its value and does not move.
///
/// A value with a unit shows it after the number (`unit`: "EV", "K", "%"). A slider whose
/// direction is not obvious names its two ends under it (`ends`: "warmer", "cooler"). A line
/// under the slider (`note`) says what governs it when it is disabled, or what it is tied to; it
/// is also what assistive technologies read as the slider's hint.
///
/// With `.labelsHidden()` only the slider is drawn, for a caller that shows the value itself
/// (the zoom under the photo). The title is still what assistive technologies read.
public extension EnvironmentValues {
    /// Whether a `ParameterSlider` takes the keyboard focus, for its arrows, Delete and Space.
    /// Off, a click with the pointer leaves the keys where they were and draws no focus ring.
    /// The app sets it from the system's "Keyboard navigation" setting.
    @Entry var slidersTakeKeyboardFocus = false
}

public struct ParameterSlider: View {
    @Environment(\.locale) private var locale
    private let title: LocalizedStringKey
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let defaultValue: Double
    private let fractionDigits: Int
    private let showsSign: Bool
    private let isOn: Binding<Bool>?
    private let unit: String?
    private let ends: SliderEnds?
    private let note: LocalizedStringKey?

    @Environment(\.labelsVisibility) private var labelsVisibility
    @Environment(\.slidersTakeKeyboardFocus) private var takesKeyboardFocus
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameters:
    ///   - step: the value snaps to multiples of this.
    ///   - defaultValue: restored by a double-click or Delete.
    ///   - fractionDigits: decimals shown in the value.
    ///   - showsSign: show `+` for positive values (for offsets around zero).
    ///   - isOn: for a parameter that can be switched off: adds the switch to the row.
    ///   - unit: written after the value, as it is (a symbol: "EV", "K", "µm", "%").
    ///   - ends: what the two ends of the slider do, under it.
    ///   - note: a line under the slider: why it is disabled, or what it is tied to.
    public init(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 0.01,
        defaultValue: Double = 0,
        fractionDigits: Int = 2,
        showsSign: Bool = false,
        isOn: Binding<Bool>? = nil,
        unit: String? = nil,
        ends: SliderEnds? = nil,
        note: LocalizedStringKey? = nil,
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.fractionDigits = fractionDigits
        self.showsSign = showsSign
        self.isOn = isOn
        self.unit = unit
        self.ends = ends
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if labelsVisibility != .hidden {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .foregroundStyle(isEnabled ? .primary : .tertiary)
                    Spacer()
                    // `Text` formats with the environment's locale, so the value follows the
                    // language of the view it is in.
                    Text(verbatim: formattedValue)
                        .font(Typography.value)
                        .foregroundStyle(valueStyle)
                    if let isOn {
                        Toggle(isOn: isOn) { Text(title) }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }
            }
            // Stepping is done in the binding: a stepped Slider draws a tick mark for every step.
            Slider(value: steppedValue, in: range, neutralValue: defaultValue) {
                Text(title)
            }
            .labelsHidden()
            .disabled(isSwitchedOff)
            .accessibilityHint(note.map { Text($0) } ?? Text(verbatim: ""))
            // The keyboard focus is on the whole component, below.
            .focusable(false)
            // Assistive technologies adjust by one step too, not by a tenth of the range.
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 1)
                case .decrement: move(by: -1)
                @unknown default: break
                }
            }
            if let ends, labelsVisibility != .hidden {
                HStack(alignment: .firstTextBaseline) {
                    Text(ends.leading)
                    Spacer()
                    Text(ends.trailing)
                }
                .font(Typography.caption)
                .foregroundStyle(isEnabled && !isSwitchedOff ? .secondary : .tertiary)
                .accessibilityHidden(true)
            }
            if let note, labelsVisibility != .hidden {
                Text(note)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: reset)
        // Where sliders take the keys, a click or Tab gives them this one's (the system's own
        // slider takes them only through Tab with "Keyboard navigation" on).
        .focusable(takesKeyboardFocus, interactions: .edit)
        .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in
            move(by: 1)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in
            move(by: -1)
            return .handled
        }
        .onKeyPress(keys: Self.deleteKeys) { _ in
            reset()
            return .handled
        }
        .onKeyPress(.space) {
            guard let isOn else { return .ignored }
            isOn.wrappedValue.toggle()
            return .handled
        }
        .help("Double-click to reset")
        .accessibilityAction(named: "Reset", reset)
    }

    /// The Delete key arrives as U+007F on a Mac keyboard, while `KeyEquivalent.delete` is
    /// U+0008: match both, and Forward Delete.
    private static let deleteKeys: Set<KeyEquivalent> = [.delete, .deleteForward, KeyEquivalent("\u{7F}")]

    private func reset() {
        guard !isSwitchedOff else { return }
        value = defaultValue
    }

    /// Whether the parameter has a switch and it is off.
    private var isSwitchedOff: Bool {
        isOn?.wrappedValue == false
    }

    /// The value is dimmed at the default, and more when the parameter is switched off or the
    /// slider disabled.
    private var valueStyle: HierarchicalShapeStyle {
        if isSwitchedOff || !isEnabled {
            return .tertiary
        }
        return isAtDefault ? .secondary : .primary
    }

    /// Whether the value is the default, to less than half a step.
    private var isAtDefault: Bool {
        abs(value - defaultValue) < step / 2
    }

    /// Moves the value by whole steps, staying on the grid of steps and inside the range.
    private func move(by steps: Double) {
        guard !isSwitchedOff else { return }
        let moved = ((value / step).rounded() + steps) * step
        value = min(max(moved, range.lowerBound), range.upperBound)
    }

    private var steppedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = ($0 / step).rounded() * step },
        )
    }

    /// The value as the row writes it, in the view's language, with its unit.
    private var formattedValue: String {
        let number = value.formatted(valueFormat.locale(locale))
        return unit.map { "\(number) \($0)" } ?? number
    }

    private var valueFormat: FloatingPointFormatStyle<Double> {
        .number
            .precision(.fractionLength(fractionDigits))
            // A large value is read as one number: a temperature is "5200", not "5,200".
            .grouping(.never)
            .sign(strategy: showsSign ? .always(includingZero: false) : .automatic)
    }
}

/// What the two ends of a slider do to the photo, written under it: "warmer" and "cooler".
public struct SliderEnds {
    public let leading: LocalizedStringKey
    public let trailing: LocalizedStringKey

    public init(_ leading: LocalizedStringKey, _ trailing: LocalizedStringKey) {
        self.leading = leading
        self.trailing = trailing
    }
}

#Preview("Parameter sliders") {
    @Previewable @State var exposure = 0.3
    @Previewable @State var printExposure = 1.0
    @Previewable @State var filter = -12.0
    @Previewable @State var grain = 0.35
    @Previewable @State var grainIsOn = true

    VStack(alignment: .leading, spacing: Spacing.l) {
        ParameterSlider("Exposure", value: $exposure, in: -5 ... 5, step: 0.1, fractionDigits: 1, showsSign: true)
        ParameterSlider("Print exposure", value: $printExposure, in: 0.2 ... 3, defaultValue: 1)
        ParameterSlider("Yellow filter", value: $filter, in: -50 ... 50, step: 1, fractionDigits: 0, showsSign: true)
        ParameterSlider(
            "A value in the thousands", value: .constant(5250), in: 2000 ... 12000,
            step: 50, defaultValue: 4500, fractionDigits: 0,
        )
        ParameterSlider(
            "A long parameter name that has to share the row with its value",
            value: $filter, in: -50 ... 50, step: 1, fractionDigits: 0,
        )
        ParameterSlider("At its default", value: .constant(0.7), in: 0 ... 2, step: 0.05, defaultValue: 0.7)
        ParameterSlider("At the end of its range", value: .constant(3), in: 0.2 ... 3, defaultValue: 1)
        ParameterSlider("Disabled", value: .constant(0.4), in: 0 ... 1, defaultValue: 0.2)
            .disabled(true)
        ParameterSlider("Grain", value: $grain, in: 0.05 ... 1, defaultValue: 0.2, isOn: $grainIsOn)
        ParameterSlider("Switched off", value: .constant(1.5), in: 0 ... 3, defaultValue: 1, isOn: .constant(false))
        ParameterSlider("Zoom", value: $exposure, in: -5 ... 5, step: 0.1)
            .labelsHidden()
    }
    .padding(Spacing.l)
    .frame(width: 320)
}
