import AlteraluxKit
import DesignSystem
import SwiftUI

/// The bar under the photo while it is cropped, in place of the zoom: the shape of the frame,
/// upright or lying down, a quarter turn and a mirror, the straightening, and the way out
/// (Reset, Cancel, Done). Return keeps
/// the frame, Escape lets it go.
struct CropControls: View {
    @Environment(AppModel.self) private var model
    let session: CropSession

    /// Width of the straightening slider, in points: it gives way first when the window is small.
    private static let sliderWidth: ClosedRange<CGFloat> = 110 ... 200

    var body: some View {
        HStack(spacing: Spacing.m) {
            Picker("Aspect Ratio", selection: aspect) {
                ForEach(CropAspect.allCases) { aspect in
                    Text(verbatim: aspect.title(isUpright: session.isUpright)).tag(aspect)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("The shape of the frame")

            Picker("Orientation", selection: upright) {
                Label("Landscape", systemImage: "rectangle").tag(false)
                Label("Portrait", systemImage: "rectangle.portrait").tag(true)
            }
            .labelStyle(.iconOnly)
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(!session.aspect.hasOrientation)
            .help("Lay the frame down or stand it upright")

            Button {
                model.turnCropLeft()
            } label: {
                Label("Rotate Left", systemImage: "rotate.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Turn the photo a quarter to the left")

            Button {
                model.flipCrop()
            } label: {
                Label("Flip Horizontally", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Mirror the photo left to right")

            Spacer(minLength: 0)

            ParameterSlider(
                "Straighten", value: angle, in: PhotoCrop.angleRange, step: 0.1, defaultValue: 0,
                fractionDigits: 1, showsSign: true,
            )
            .frame(minWidth: Self.sliderWidth.lowerBound, maxWidth: Self.sliderWidth.upperBound)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.s) {
                Button("Reset") { model.resetCrop() }
                    .help("Back to the whole photo as it was shot")
                Button("Cancel", role: .cancel) { model.cancelCrop() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { model.confirmCrop() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xs)
        .background(Color.DS.viewerSurround)
    }

    private var aspect: Binding<CropAspect> {
        Binding(get: { session.aspect }, set: { model.setCropAspect($0) })
    }

    private var upright: Binding<Bool> {
        Binding(get: { session.isUpright }, set: { model.setCropUpright($0) })
    }

    private var angle: Binding<Double> {
        Binding(get: { model.cropAngle }, set: { model.cropAngle = $0 })
    }
}
