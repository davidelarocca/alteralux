import DesignSystem
import SwiftUI

/// The zoom: fit, 100%, and a slider between a small step out and a small step in, with the
/// scale beside it. It floats on the system's glass over the bottom trailing corner of the
/// photo, with the strip shown or hidden.
///
/// The slider's neutral point is the fitted photo: it fills from there, and a double-click or
/// Delete goes back to it.
struct ZoomControls: View {
    @Environment(AppModel.self) private var model

    /// Width of the slider, in points.
    private static let sliderWidth: CGFloat = 130
    /// Room for "800%", so the controls do not move while the scale changes.
    private static let scaleWidth: CGFloat = 40

    var body: some View {
        GlassGroup {
            Picker("Zoom", selection: preset) {
                Text("Fit").tag(ZoomPreset?.some(.fit))
                Text("100%").tag(ZoomPreset?.some(.actualSize))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            step(.zoomOut, title: "Zoom Out", systemImage: "minus")
            ParameterSlider(
                "Zoom", value: level, in: AppModel.zoomLevelRange,
                step: AppModel.zoomLevelStep, defaultValue: model.fitZoomLevel,
            )
            .labelsHidden()
            .frame(width: Self.sliderWidth)
            step(.zoomIn, title: "Zoom In", systemImage: "plus")
            Text(model.viewerZoom.scale, format: .percent.precision(.fractionLength(0)))
                .font(Typography.technical)
                .foregroundStyle(.secondary)
                .frame(width: Self.scaleWidth, alignment: .trailing)
                .accessibilityLabel("Zoom")
        }
        .disabled(!model.canZoom)
    }

    private func step(_ command: ZoomCommand, title: LocalizedStringKey, systemImage: String) -> some View {
        Button {
            model.zoom(command)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    /// Fit or 100% when the viewer shows one of them, nothing in between.
    private var preset: Binding<ZoomPreset?> {
        Binding(
            get: { model.zoomPreset },
            set: { preset in
                switch preset {
                case .fit: model.zoom(.fit)
                case .actualSize: model.zoom(.actualSize)
                case nil: break
                }
            },
        )
    }

    private var level: Binding<Double> {
        Binding(
            get: { model.zoomLevel },
            set: { model.setZoomLevel($0) },
        )
    }
}
