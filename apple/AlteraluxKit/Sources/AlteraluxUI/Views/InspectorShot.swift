import AlteraluxKit
import DesignSystem
import SwiftUI

// The shot section's controls (ADR 0016): what is set before the film sees the photo. The
// exposure and the white balance are each a title with its "Auto" switch on the same row: on, the
// mode takes care of it and nothing else is shown; off, the sliders appear under it (ADR 0020).

/// The exposure: left to the camera's meter, or a slider. With the meter on, its method and a
/// compensation are in the meter's own group, closed (`MeterDetails`).
struct ExposureControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        InspectorSubheading(
            "Exposure", isOn: $model.isExposureAutomatic, switchTitle: "Auto", switchLabel: "Automatic exposure",
        )
        .help("On, the scene is metered as a camera would. Off, the exposure is yours, from where the meter left it.")
        if !model.settings.autoExposure {
            ParameterSlider(
                "Exposure", value: $model.settings.exposureEV, in: AppModel.exposureRange,
                step: AppModel.exposureStep, fractionDigits: 1, showsSign: true, unit: "EV",
                note: model.settings.printCompensatesExposure && !model.settings.scanFilm
                    ? "The lab compensates it at the print: it changes the negative, not the brightness." : nil,
            )
            .help("Brightens or darkens the photo before the film sees it, in stops.")
        }
    }
}

/// The meter's group: how it weighs the scene, and a compensation of what it measured. Both are
/// the meter's, so they wait for it to be on.
struct MeterDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        let off: LocalizedStringKey = "Off: switch the automatic exposure on to use the meter."
        Group {
            WindowPopUp(
                "Metering", selection: $settings.meteringMethod,
                options: MeteringMethod.allCases.map { WindowPopUpOption($0, title: String(localized: $0.title)) },
            )
            .help("How the meter weighs the scene: the center, the whole frame, the highlights.")
            ParameterSlider(
                "Exposure compensation", value: $settings.exposureEV, in: AppModel.exposureRange,
                step: AppModel.exposureStep, fractionDigits: 1, showsSign: true, unit: "EV",
                note: settings.autoExposure ? nil : off,
            )
            .help("Added to what the meter measured, in stops: for a look that is brighter or darker on every photo.")
        }
        .governed(!settings.autoExposure, reason: off)
    }
}

/// The scene's highlights and shadows: light taken from, or given to, one end of the scene after
/// the exposure and before the film (ADR 0019). In view under a title of their own, right after the
/// exposure they are measured from: they are the hand's whether the exposure is automatic or not.
struct SceneToneControls: View {
    @Binding var tone: SceneTone

    var body: some View {
        InspectorSubheading("Highlights and shadows")
        ParameterSlider(
            "Highlights", value: percent($tone.highlights), in: -100 ... 100, step: 1, fractionDigits: 0,
            showsSign: true, ends: SliderEnds("Dimmer", "Brighter"),
        )
        .help("Darkens or brightens the brightest parts of the scene before the film sees them.")
        ParameterSlider(
            "Shadows", value: percent($tone.shadows), in: -100 ... 100, step: 1, fractionDigits: 0,
            showsSign: true, ends: SliderEnds("Deeper", "More open"),
        )
        .help("Deepens or lifts the darkest parts of the scene before the film sees them.")
    }
}

/// The white balance: chosen from the light measured in the photo, or temperature and tint. A
/// photo that is not a RAW has its white balance in its pixels: a line says so.
struct WhiteBalanceControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let neutral = model.neutralWhiteBalance

        if model.whiteBalanceIsFixed {
            InspectorSubheading("White balance", note: "White balance can be chosen for RAW photos only.")
        } else {
            Group {
                InspectorSubheading(
                    "White balance", isOn: $model.isWhiteBalanceAutomatic, switchTitle: "Auto",
                    switchLabel: "Automatic white balance",
                    note: model.isWhiteBalanceAutomatic && model.cameraChoseWhiteBalance
                        ? "The camera chose this white balance itself, from the scene: it is kept." : nil,
                )
                .help("On, it starts from the light measured in the photo where the camera's white balance is far from it.")
                if !model.isWhiteBalanceAutomatic {
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
                    )
                    .help("Corrects a green or magenta cast of the light.")
                }
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

/// What Apple's RAW decoder does before the film, where it offers it for the photo's camera:
/// highlight recovery and noise reduction, each starting from its own choice. The color noise and
/// the moiré, which few photos need, are under "More shot adjustments".
struct RawDevelopmentControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let defaults = model.rawDefaults, Self.offersMainControls(defaults) {
            if defaults.highlightRecovery != nil {
                Toggle("Highlight recovery", isOn: $model.highlightRecovery)
                    .help("Rebuilds the colors of the highlights where the sensor clipped.")
            }
            if let luminance = defaults.luminanceNoiseReduction {
                ParameterSlider(
                    "Noise reduction", value: percent($model.luminanceNoiseReduction), in: 0 ... 100,
                    step: 1, defaultValue: luminance * 100, fractionDigits: 0, unit: "%",
                )
                .help("Smooths the digital noise of the sensor before the film adds its own grain.")
            }
        }
    }
}

extension RawDevelopmentControls {
    /// Whether the decoder offers any of the controls kept in view.
    static func offersMainControls(_ defaults: RawDecodingDefaults) -> Bool {
        defaults.highlightRecovery != nil || defaults.luminanceNoiseReduction != nil
    }

    /// Whether the decoder offers any of the controls under "More shot adjustments".
    static func offersMoreControls(_ defaults: RawDecodingDefaults) -> Bool {
        defaults.colorNoiseReduction != nil || defaults.moireReduction != nil
    }
}

/// The diffusion filter in front of the lens: its strength with its switch, and which filter it is.
struct DiffusionControls: View {
    @Binding var filter: DiffusionFilterSettings

    var body: some View {
        ParameterSlider(
            "Diffusion filter", value: $filter.strength, in: 0 ... 2,
            defaultValue: 0.5, isOn: $filter.enabled,
        )
        .help("A filter in front of the lens that makes the lights glow, as a Pro-Mist does.")
        WindowPopUp(
            "Kind of filter", selection: $filter.family,
            options: DiffusionFamily.allCases.map { WindowPopUpOption($0, title: $0.title) },
        )
        .governed(!filter.enabled, reason: "Off: switch the diffusion filter on to choose its kind.")
        .help("Black Pro-Mist keeps the blacks deep; Pro-Mist lifts them; Glimmerglass sparkles; CineBloom blooms.")
    }
}

/// A fraction from 0 to 1 as a percentage, for a slider that reads in percent.
func percent(_ fraction: Binding<Double>) -> Binding<Double> {
    Binding(get: { fraction.wrappedValue * 100 }, set: { fraction.wrappedValue = $0 / 100 })
}
