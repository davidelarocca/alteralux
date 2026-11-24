import AlteraluxKit
import DesignSystem
import SwiftUI

// The shot section's controls (ADR 0016): what is set before the film sees the photo. The modes
// come first, over the sliders they govern; a governed slider stays in view, disabled, with the
// value its mode chose and a line that says why.

/// The camera's meter and the exposure on top of it. With the meter on,
/// the exposure is a compensation of what it measured; with the lab compensating the print, it
/// changes the negative rather than the brightness, and a line says so.
struct ExposureControls: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        Toggle("Automatic metering", isOn: $settings.autoExposure)
            .help("Meters the scene as a camera would; the exposure below is then added to what it measured.")
        ParameterSlider(
            settings.autoExposure ? "Exposure compensation" : "Exposure", value: $settings.exposureEV, in: -5 ... 5,
            step: 0.1, fractionDigits: 1, showsSign: true, unit: "EV",
            note: settings.printCompensatesExposure && !settings.scanFilm
                ? "The lab compensates it at the print: it changes the negative, not the brightness." : nil,
        )
        .help("Brightens or darkens the photo before the film sees it, in stops.")
    }
}

/// Temperature and tint: what the RAW decoder takes as neutral. With the automatic white balance
/// on, they show what it chose and stay still until it is switched off.
struct WhiteBalanceControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let neutral = model.neutralWhiteBalance
        let isAutomatic = model.isWhiteBalanceAutomatic

        // A photo that is not a RAW has its white balance in its pixels: a line says so, in
        // place of two sliders that could not move.
        if model.whiteBalanceIsFixed {
            Text("White balance can be chosen for RAW photos only.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        } else {
            Group {
                Toggle("Automatic white balance", isOn: $model.isWhiteBalanceAutomatic)
                    .help("Starts from the light measured in the photo where the camera's white balance is far from it.")
                if isAutomatic, model.cameraChoseWhiteBalance {
                    Text("The camera chose this white balance itself, from the scene: it is kept.")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Group {
                    ParameterSlider(
                        "Temperature", value: $model.temperature, in: model.temperatureRange,
                        step: AppModel.temperatureStep, defaultValue: neutral.temperature, fractionDigits: 0,
                        unit: "K", ends: SliderEnds("Cooler", "Warmer"),
                    )
                    .help("The color of the light the photo was taken in, in kelvin.")
                    ParameterSlider(
                        "Tint", value: $model.tint, in: AppModel.tintRange,
                        step: AppModel.tintStep, defaultValue: neutral.tint, fractionDigits: 0,
                        ends: SliderEnds("Greener", "More magenta"),
                        note: isAutomatic ? "Set by the automatic white balance." : nil,
                    )
                    .help("Corrects a green or magenta cast of the light.")
                }
                .governed(isAutomatic, reason: "Set by the automatic white balance.")
            }
            .disabled(!model.canAdjustWhiteBalance)
        }
    }
}

/// Whether the lens is corrected, where the RAW decoder, the camera's own data or a lens profile
/// know this camera's lens, with a line that says which of the last two does; otherwise a line
/// says there is nothing to correct with.
struct LensCorrectionToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle("Lens correction", isOn: $model.isLensCorrected)
            .disabled(!model.correctsLens)
            .help("Straightens the lens's curved lines, brightens its darker corners and takes away its colored fringes.")
        if model.hasPhoto, !model.correctsLens {
            Text("No correction is known for this photo's lens.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        } else if let correction = model.cameraLensCorrection {
            CameraCorrectionLine(correction: correction)
        } else if let lens = model.lensProfileName {
            Text("Lensfun profile: \(lens)")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Who corrects the lens when the camera recorded some of it: the camera alone, or with lensfun,
/// or only the vignetting after Apple's decoder.
private struct CameraCorrectionLine: View {
    let correction: CameraLensCorrection

    var body: some View {
        let lens = correction.lensName
        Group {
            switch (correction.geometrySource, correction.vignettingSource) {
            case (.apple, _):
                Text("Vignetting corrected with the camera's data")
            case (.lensfun, _):
                Text("Lensfun profile, vignetting from the camera: \(lens)")
            case (_, .lensfun):
                Text("Camera's own correction, vignetting from lensfun: \(lens)")
            default:
                Text("Camera's own correction: \(lens)")
            }
        }
        .font(Typography.caption)
        .foregroundStyle(.secondary)
    }
}

/// The lens: whether it is corrected, and the halation, the red glow the film adds around the
/// lights the lens gathers. Nothing else of the lens is in the inspector (ADR 0018).
struct LensControls: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        InspectorSubheading("Lens")
        LensCorrectionToggle()
        ParameterSlider(
            "Halation", value: $settings.halationAmount, in: 0 ... 3,
            step: 0.05, defaultValue: 1, isOn: $settings.halationEnabled,
        )
        .help("The red glow around bright lights, from light bouncing off the back of the film.")
    }
}
