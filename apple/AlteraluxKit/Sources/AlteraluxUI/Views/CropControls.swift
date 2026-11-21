import AlteraluxKit
import DesignSystem
import SwiftUI

/// The controls that float over the bottom of the photo while it is cropped, on the system's
/// glass: one piece holding the shape of the frame and whether it stands upright, a quarter turn
/// and a mirror, the straightening and Reset; beside it, round, Cancel and Done. Return keeps the
/// frame, Escape lets it go.
///
/// Where the photo is too narrow for one row, the straightening goes on a piece of its own above
/// the rest.
struct CropControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    let session: CropSession

    /// Width of the straightening slider, in points: it gives way first when the window is small.
    private static let sliderWidth: ClosedRange<CGFloat> = 120 ... 220
    /// Room for "−45.0°", so the controls do not move while the angle changes.
    private static let angleWidth: CGFloat = 48

    var body: some View {
        GlassEffectContainer(spacing: Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) {
                    GlassGroup {
                        frameTools
                        Divider()
                        straighten
                        Divider()
                        reset
                    }
                    exits
                }
                VStack(spacing: Spacing.s) {
                    GlassGroup { straighten }
                    HStack(spacing: Spacing.s) {
                        GlassGroup {
                            frameTools
                            Divider()
                            reset
                        }
                        exits
                    }
                }
            }
        }
        .controlSize(.large)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.l)
    }

    /// The frame's shape, upright or lying down, and the turns of the photo.
    @ViewBuilder private var frameTools: some View {
        // A list that opens above the button, inside the window: a menu here would open
        // downward, past the window's bottom edge.
        ChoiceListButton(
            Text(verbatim: session.aspect.title(isUpright: session.isUpright)),
            choices: aspectChoices,
            empty: Text(verbatim: ""),
        )
        .fixedSize()
        .accessibilityLabel(Text("Aspect Ratio"))
        .accessibilityValue(Text(verbatim: session.aspect.title(isUpright: session.isUpright)))
        .help("The shape of the frame")

        // A square has no side to lay down: the switch goes, rather than sit there unusable.
        if session.aspect.hasOrientation {
            Picker("Orientation", selection: upright) {
                Label("Landscape", systemImage: "rectangle").tag(false)
                Label("Portrait", systemImage: "rectangle.portrait").tag(true)
            }
            .labelStyle(.iconOnly)
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Lay the frame down or stand it upright")
        }

        Button("Rotate Left", systemImage: "rotate.left") { model.turnCropLeft() }
            .labelStyle(.iconOnly)
            .help("Turn the photo a quarter to the left")
        Button(
            "Flip Horizontally",
            systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
        ) { model.flipCrop() }
            .labelStyle(.iconOnly)
            .help("Mirror the photo left to right")
    }

    /// The straightening on one row: its name, the slider, the angle.
    private var straighten: some View {
        HStack(spacing: Spacing.s) {
            Text("Straighten")
                .fixedSize()
                .accessibilityHidden(true)
            ParameterSlider(
                "Straighten", value: angle, in: PhotoCrop.angleRange, step: 0.1, defaultValue: 0,
                fractionDigits: 1, showsSign: true,
            )
            .labelsHidden()
            .frame(minWidth: Self.sliderWidth.lowerBound, maxWidth: Self.sliderWidth.upperBound)
            Text(verbatim: angleText)
                .font(Typography.technical)
                .foregroundStyle(model.cropAngle == 0 ? .secondary : .primary)
                .frame(width: Self.angleWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// Apart from Cancel and Done, inside the controls of the frame, so it is not pressed for
    /// one of them.
    private var reset: some View {
        Button("Reset") { model.resetCrop() }
            .help("Back to the whole photo as it was shot")
    }

    private var exits: some View {
        HStack(spacing: Spacing.s) {
            Button("Cancel", systemImage: "xmark", role: .cancel) { model.cancelCrop() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
                .help("Leave the frame as it was")
            Button("Done", systemImage: "checkmark") { model.confirmCrop() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .help("Keep this frame")
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        // As tall as the piece of glass beside them.
        .controlSize(.extraLarge)
        .fixedSize()
    }

    /// The angle in the view's language, with its degree sign: "+1,5°".
    private var angleText: String {
        let number = model.cropAngle.formatted(
            .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))
                .locale(locale),
        )
        return number + "°"
    }

    /// Every shape of the frame, the one it has checked.
    private var aspectChoices: [Choice] {
        CropAspect.allCases.map { aspect in
            Choice(
                id: String(describing: aspect.id),
                title: aspect.title(isUpright: session.isUpright),
                mark: aspect == session.aspect ? .all : .off,
            ) { model.setCropAspect(aspect) }
        }
    }

    private var upright: Binding<Bool> {
        Binding(get: { session.isUpright }, set: { model.setCropUpright($0) })
    }

    private var angle: Binding<Double> {
        Binding(get: { model.cropAngle }, set: { model.cropAngle = $0 })
    }
}
