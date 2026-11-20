import SwiftUI

/// A labelled slider with its value shown on the right.
///
/// The track fills from the default value to the current one, in either direction, so the
/// neutral point of a parameter and how far it has been moved are both in view. At the default
/// nothing is filled and the value is dimmed.
///
/// Double-click resets it to its default. It takes the keyboard focus with Tab
/// whatever the system's "Keyboard navigation" setting: the arrow keys move it
/// one step and Delete resets it.
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
                    .foregroundStyle(isAtDefault ? .secondary : .primary)
            }
            // Stepping is done in the binding.
            SliderTrack(value: steppedValue, range: range, neutral: defaultValue)
                // Assistive technologies get a system slider: its role, its value and its range.
                .accessibilityRepresentation {
                    Slider(value: steppedValue, in: range) {
                        Text(title)
                    }
                    // They adjust by one step too, not by a tenth of the range.
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: move(by: 1)
                        case .decrement: move(by: -1)
                        @unknown default: break
                        }
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: reset)
        // The system gives a slider the keyboard focus only when "Keyboard navigation" is on in
        // System Settings. The sliders are the main controls here, so they always take it.
        .focusable(interactions: .edit)
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
        .help("Double-click to reset")
        .accessibilityAction(named: "Reset", reset)
    }

    /// The Delete key arrives as U+007F on a Mac keyboard, while `KeyEquivalent.delete` is
    /// U+0008: match both, and Forward Delete.
    private static let deleteKeys: Set<KeyEquivalent> = [.delete, .deleteForward, KeyEquivalent("\u{7F}")]

    private func reset() {
        value = defaultValue
    }

    /// Whether the value is the default, to less than half a step.
    private var isAtDefault: Bool {
        abs(value - defaultValue) < step / 2
    }

    /// Moves the value by whole steps, staying on the grid of steps and inside the range.
    private func move(by steps: Double) {
        let moved = ((value / step).rounded() + steps) * step
        value = min(max(moved, range.lowerBound), range.upperBound)
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

/// Sizes and colors of the slider's track. Grays only: nothing saturated sits next to the photo.
private enum SliderMetrics {
    /// The height of the area that takes the pointer.
    static let height: CGFloat = 16
    static let trackHeight: CGFloat = 2
    static let thumbDiameter: CGFloat = 12
    static let tickWidth: CGFloat = 1
    static let tickHeight: CGFloat = 10
    static let track = Color.primary.opacity(0.16)
    static let fill = Color.primary.opacity(0.8)
    static let tick = Color.primary.opacity(0.36)
    /// Opaque, unlike the label colors: the mark and the fill must not show through the thumb.
    static let thumbOnDark = Color(white: 0.92)
    static let thumbOnLight = Color(white: 0.16)
    static let disabledOpacity = 0.4
}

/// The track of a `ParameterSlider`: a thin line, a mark at the neutral value, the fill between
/// that mark and the thumb. Dragging or clicking anywhere on it sets the value.
private struct SliderTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let neutral: Double

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumbX = position(of: value, in: width)
            let neutralX = position(of: neutral, in: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SliderMetrics.track)
                    .frame(height: SliderMetrics.trackHeight)
                Rectangle()
                    .fill(SliderMetrics.fill)
                    .frame(width: abs(thumbX - neutralX), height: SliderMetrics.trackHeight)
                    .offset(x: min(thumbX, neutralX))
                Rectangle()
                    .fill(SliderMetrics.tick)
                    .frame(width: SliderMetrics.tickWidth, height: SliderMetrics.tickHeight)
                    .offset(x: neutralX - SliderMetrics.tickWidth / 2)
                Circle()
                    .fill(colorScheme == .dark ? SliderMetrics.thumbOnDark : SliderMetrics.thumbOnLight)
                    .frame(width: SliderMetrics.thumbDiameter, height: SliderMetrics.thumbDiameter)
                    .offset(x: thumbX - SliderMetrics.thumbDiameter / 2)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in value = value(at: drag.location.x, in: width) },
            )
        }
        // Positions are computed for both directions below: the drawing itself is not mirrored.
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: SliderMetrics.height)
        .opacity(isEnabled ? 1 : SliderMetrics.disabledOpacity)
    }

    /// The part of the track the thumb's center can travel.
    private func travel(in width: CGFloat) -> CGFloat {
        max(width - SliderMetrics.thumbDiameter, 1)
    }

    private var isRightToLeft: Bool {
        layoutDirection == .rightToLeft
    }

    /// The x of the thumb's center for `value`, clamped to the range. Larger values are towards
    /// the trailing edge, so on the left in a right-to-left language.
    private func position(of value: Double, in width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let fraction = span > 0 ? (clamped - range.lowerBound) / span : 0
        let directed = isRightToLeft ? 1 - fraction : fraction
        return SliderMetrics.thumbDiameter / 2 + travel(in: width) * directed
    }

    private func value(at location: CGFloat, in width: CGFloat) -> Double {
        let directed = min(max((location - SliderMetrics.thumbDiameter / 2) / travel(in: width), 0), 1)
        let fraction = isRightToLeft ? 1 - directed : directed
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
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
        ParameterSlider("At its default", value: .constant(0.7), in: 0 ... 2, step: 0.05, defaultValue: 0.7)
        ParameterSlider("At the end of its range", value: .constant(3), in: 0.2 ... 3, defaultValue: 1)
        ParameterSlider("Disabled", value: .constant(0.4), in: 0 ... 1, defaultValue: 0.2)
            .disabled(true)
    }
    .padding(Spacing.l)
    .frame(width: 320)
}
