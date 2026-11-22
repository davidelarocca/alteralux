import AlteraluxKit
import DesignSystem
import SwiftUI

// The controls of spektrafilm beyond the main ones (ADR 0016), under "More adjustments" in each
// section of the inspector. Every slider starts from, and goes back to, the engine's default.

/// A section's technical controls, in a collapsible section of their own right under it, closed
/// until the user opens it and then as the user left it. A disclosure group inside a collapsible
/// section of a form does not open on macOS (see docs/PITFALLS.md).
struct MoreAdjustments<Content: View>: View {
    @AppStorage private var isExpanded: Bool
    private let title: LocalizedStringKey
    private let content: Content

    /// - Parameter key: the section, for the open or closed state to be kept apart.
    init(_ key: String, title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        _isExpanded = AppStorage(wrappedValue: false, "inspector.\(key).more.isExpanded")
        self.title = title
        self.content = content()
    }

    var body: some View {
        InspectorSection(title, isExpanded: $isExpanded) {
            content
        }
    }
}

/// A slider for a whole number, such as a count of layers or bounces.
private func whole(_ value: Binding<Int>) -> Binding<Double> {
    Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) })
}

/// The shot's details: the lens's softness, the diffusion filter's shape, and the moiré reduction
/// of the RAW decoder where it offers it.
struct ShotDetails: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: DevelopSettings

    var body: some View {
        @Bindable var model = model
        InspectorSubheading("Lens")
        ParameterSlider("Lens blur", value: $settings.lensBlur, in: 0 ... 100, step: 1, fractionDigits: 0, unit: "µm")
            .help("Blurs the image on the film, as a soft or vintage lens would. 0 is a sharp lens.")
        DiffusionDetails(filter: $settings.diffusionFilter)
        if let moire = model.rawDefaults?.moireReduction {
            InspectorSubheading("RAW development")
            ParameterSlider(
                "Moiré reduction", value: percent($model.moireReduction), in: 0 ... 100,
                step: 1, defaultValue: moire * 100, fractionDigits: 0, unit: "%",
            )
            .help("Takes away the colored ripples that fine patterns make on the sensor.")
        }
    }
}

private struct DiffusionDetails: View {
    @Binding var filter: DiffusionFilterSettings

    var body: some View {
        InspectorSubheading(
            "Diffusion filter", note: filter.enabled ? nil : "Off: switch the diffusion filter on in Shot to shape it.",
        )
        Group {
            ParameterSlider("Filter scale", value: $filter.spatialScale, in: 0.1 ... 3, defaultValue: 1, unit: "×")
                .help("How far the whole glow reaches, as the filter would on a larger or smaller frame.")
            ParameterSlider("Glow", value: $filter.haloIntensity, in: 0 ... 2, defaultValue: 1)
                .help("The soft halo around the lights.")
            ParameterSlider("Glow size", value: $filter.haloSize, in: 0.1 ... 3, defaultValue: 1, unit: "×")
                .help("How wide the halo spreads.")
            ParameterSlider(
                "Glow warmth", value: $filter.haloWarmth, in: -1.5 ... 1.5, showsSign: true,
                ends: SliderEnds("Cooler", "Warmer"),
            )
            .help("The color of the halo, from cool to warm.")
            ParameterSlider("Core", value: $filter.coreIntensity, in: 0 ... 2, defaultValue: 1)
                .help("The bright glow right around each light.")
            ParameterSlider("Core size", value: $filter.coreSize, in: 0.1 ... 3, defaultValue: 1, unit: "×")
                .help("How wide that bright glow is.")
            ParameterSlider("Bloom", value: $filter.bloomIntensity, in: 0 ... 2, defaultValue: 1)
                .help("The faint veil the filter lays over the whole picture, which lifts the shadows.")
            ParameterSlider("Bloom size", value: $filter.bloomSize, in: 0.1 ... 3, defaultValue: 1, unit: "×")
                .help("How far that veil spreads.")
        }
        .disabled(!filter.enabled)
    }
}

/// The film's details: the grain's softness and layers, the halation and scatter, the reach of
/// the color separation.
struct FilmDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        InspectorSubheading("Grain", note: settings.grainEnabled ? nil : "Off: switch Grain on in Film to shape it.")
        Group {
            ParameterSlider("Grain softness", value: $settings.grainDetail.blur, in: 0 ... 3, defaultValue: 0.65, unit: "px")
                .help("Softens the grain: 0 is crisp, higher is smoother.")
            ParameterSlider(
                "Grain layers", value: whole($settings.grainDetail.subLayers), in: 1 ... 4,
                step: 1, defaultValue: 1, fractionDigits: 0,
            )
            .help("In how many layers the grain forms: more layers make it finer and less regular.")
        }
        .disabled(!settings.grainEnabled)
        HalationDetails(settings: $settings)
        InspectorSubheading(
            "Color separation", note: settings.couplersEnabled ? nil : "Off: switch Color separation on in Film to shape it.",
        )
        Group {
            ParameterSlider(
                "Reach", value: $settings.couplersDetail.diffusionSize, in: 0 ... 100,
                step: 1, defaultValue: 20, fractionDigits: 0, unit: "µm",
            )
            .help("How far each layer holds back its neighbors: wider gives softer, larger halos of color at the edges.")
            ParameterSlider(
                "Long reach", value: $settings.couplersDetail.diffusionTail, in: 0 ... 400,
                step: 5, defaultValue: 200, fractionDigits: 0, unit: "µm",
            )
            .help("The faint, far part of that reach.")
            ParameterSlider("Weight of the long reach", value: $settings.couplersDetail.tailWeight, in: 0 ... 1, defaultValue: 0.06)
                .help("How much the far part counts against the near one.")
        }
        .disabled(!settings.couplersEnabled)
    }
}

private struct HalationDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        // The engine applies the scatter inside the halation: one switch turns both off.
        InspectorSubheading(
            "Halation and scatter",
            note: settings.halationEnabled
                ? nil : "Off with Halation: the film spreads light in one go, so the scatter stops too.",
        )
        Group {
            ParameterSlider(
                "Halation size", value: $settings.halationDetail.halationScale, in: 0.1 ... 5, defaultValue: 1, unit: "×",
            )
            .help("How wide the red glow spreads around the lights.")
            ParameterSlider("Scatter", value: $settings.scatterAmount, in: 0 ... 3, defaultValue: 1)
                .help("Light spreading inside the emulsion, which softens fine detail.")
            ParameterSlider("Scatter size", value: $settings.halationDetail.scatterScale, in: 0.1 ... 5, defaultValue: 1, unit: "×")
                .help("How far that light spreads.")
            ParameterSlider(
                "Reflections off the film base", value: whole($settings.halationDetail.bounces), in: 1 ... 5,
                step: 1, defaultValue: 3, fractionDigits: 0,
            )
            .help("How many times light bounces off the back of the film: more reflections, wider halos.")
            ParameterSlider(
                "Fading of each reflection", value: $settings.halationDetail.bounceDecay, in: 0 ... 1, defaultValue: 0.5,
            )
            .help("How much light each reflection loses: higher fades the outer halos faster.")
            Toggle("Take the halo's light from the highlights", isOn: $settings.halationDetail.renormalize)
                .help("The light the halo spreads is taken from the light that made it, so the highlights do not grow brighter.")
        }
        .disabled(!settings.halationEnabled)
    }
}

/// The print's details: the pre-flash's color, the glare and the paper's curves rebuilt.
struct PrintDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        InspectorSubheading("Pre-flash", note: settings.preflashExposure == 0 ? "Off: raise Pre-flash in Print to color it." : nil)
        Group {
            ParameterSlider(
                "Pre-flash yellow filter", value: $settings.preflashYellowShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true, ends: SliderEnds("Yellower", "Bluer"),
            )
            .help("The yellow filter of the pre-flash alone: it colors the greyed whites.")
            ParameterSlider(
                "Pre-flash magenta filter", value: $settings.preflashMagentaShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true, ends: SliderEnds("More magenta", "Greener"),
            )
            .help("The magenta filter of the pre-flash alone.")
        }
        .disabled(settings.preflashExposure == 0)
        InspectorSubheading("Glare")
        ParameterSlider(
            "Glare", value: percent($settings.printGlare.percent), in: 0 ... 20, step: 0.5,
            defaultValue: 3, fractionDigits: 1, isOn: $settings.printGlare.enabled, unit: "%",
        )
        .help("Stray light in the enlarger and on the paper, which veils the shadows.")
        Group {
            ParameterSlider("Glare roughness", value: $settings.printGlare.roughness, in: 0 ... 2, defaultValue: 0.7)
                .help("How unevenly the stray light falls: higher is blotchier.")
            ParameterSlider("Glare softness", value: $settings.printGlare.blur, in: 0 ... 5, defaultValue: 0.5, unit: "px")
                .help("How soft the stray light's edges are.")
        }
        .disabled(!settings.printGlare.enabled)
        PrintCurvesDetails(curves: $settings.printCurves)
    }
}

private struct PrintCurvesDetails: View {
    @Binding var curves: PrintCurvesSettings

    var body: some View {
        InspectorSubheading("Paper curves")
        Toggle("Rebuild the paper's curves", isOn: $curves.enabled)
            .help("Rebuilds the paper's response from its model, so its contrast can be changed below.")
        Group {
            ParameterSlider("Paper contrast", value: $curves.gamma, in: 0.5 ... 2, defaultValue: 1, unit: "×")
                .help("The paper's contrast as a whole, as a harder or softer grade would give.")
            ParameterSlider("Contrast of the fast layer", value: $curves.gammaFast, in: 0.5 ... 2, defaultValue: 1, unit: "×")
                .help("The contrast of the paper's fast emulsion, which sets the lighter tones.")
            ParameterSlider("Contrast of the slow layer", value: $curves.gammaSlow, in: 0.5 ... 2, defaultValue: 1, unit: "×")
                .help("The contrast of the paper's slow emulsion, which sets the deeper tones.")
            ParameterSlider("Red contrast", value: $curves.gammaRed, in: 0.5 ... 2, defaultValue: 1, unit: "×")
                .help("The contrast of the paper's red-sensitive layer alone: it shifts colors between light and dark tones.")
            ParameterSlider("Green contrast", value: $curves.gammaGreen, in: 0.5 ... 2, defaultValue: 1, unit: "×")
                .help("The contrast of the green-sensitive layer alone.")
            ParameterSlider("Blue contrast", value: $curves.gammaBlue, in: 0.5 ... 2, defaultValue: 1, unit: "×")
                .help("The contrast of the blue-sensitive layer alone.")
            ParameterSlider(
                "Exhausted developer", value: percent($curves.developerExhaustion), in: 0 ... 100,
                step: 1, fractionDigits: 0, unit: "%",
                note: curves.enabled ? nil : "Off: switch on Rebuild the paper's curves to change them.",
            )
            .help("A tired developer: it flattens the deepest blacks of the print.")
        }
        .disabled(!curves.enabled)
    }
}

/// The scan's details: the sharpening's radius, the scanner's softness, its white and black
/// points, and, last, how colors enter the film and leave the scan.
struct ScanDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        InspectorSubheading("Sharpening")
        ParameterSlider("Sharpening radius", value: $settings.sharpenRadius, in: 0 ... 3, defaultValue: 0.7, unit: "px")
            .help("How wide the edges the sharpening finds: small for fine detail, larger for outlines.")
        InspectorSubheading("Scanner")
        ParameterSlider("Scanner blur", value: $settings.scanner.lensBlur, in: 0 ... 5, unit: "px")
            .help("Softens the scan, as a scanner's own lens would. 0 is sharp.")
        Toggle("Set the white point", isOn: $settings.scanner.correctsWhite)
            .help("Makes the brightest tone of the scan pure white.")
        ParameterSlider(
            "White point", value: percent($settings.scanner.whiteLevel), in: 50 ... 100,
            step: 0.5, defaultValue: 98, fractionDigits: 1, unit: "%",
        )
        .disabled(!settings.scanner.correctsWhite)
        .help("Which level of the scan becomes white: lower brightens the scan.")
        Toggle("Set the black point", isOn: $settings.scanner.correctsBlack)
            .help("Makes the deepest tone of the scan pure black.")
        ParameterSlider(
            "Black point", value: percent($settings.scanner.blackLevel), in: 0 ... 50,
            step: 0.5, defaultValue: 1, fractionDigits: 1, unit: "%",
        )
        .disabled(!settings.scanner.correctsBlack)
        .help("Which level of the scan becomes black: higher deepens the shadows.")
        ColorDetails(color: $settings.color)
    }
}

private struct ColorDetails: View {
    @Binding var color: ColorSettings

    var body: some View {
        InspectorSubheading("Color (advanced)", note: "Color science: the defaults are spektrafilm's own.")
        WindowPopUp(
            "Colors outside the screen", selection: $color.outputGamut,
            options: OutputGamutCompression.allCases.map { WindowPopUpOption($0, title: $0.title) },
        )
        .help("How colors the screen cannot show are brought inside it (gamut compression).")
        WindowPopUp(
            "Colors outside the film", selection: $color.inputGamut,
            options: InputGamutCompression.allCases.map { WindowPopUpOption($0, title: String(localized: $0.title)) },
        )
        .help("How colors of the photo the film could not see are brought inside what it can (input gamut compression).")
        Toggle("Modern color adaptation (CAT16)", isOn: $color.cat16)
            .help("Adapts the photo's colors to the film's light with CAT16 rather than the older CAT02: better blues and violets.")
        WindowPopUp(
            "From colors to light", selection: $color.upsampling,
            options: SpectralUpsampling.allCases.map { WindowPopUpOption($0, title: String(localized: $0.title)) },
        )
        .help("How the photo's colors become the spectrum of light that reaches the film's layers (spectral upsampling).")
    }
}

// MARK: - Titles

extension MeteringMethod {
    var title: LocalizedStringResource {
        switch self {
        case .average: "Average"
        case .median: "Median"
        case .centerWeighted: "Center-weighted"
        case .partial: "Partial"
        case .matrix: "Matrix"
        case .multiZone: "Multi-zone"
        case .highlightWeighted: "Highlight-weighted"
        }
    }
}

extension DiffusionFamily {
    /// The filters' own names.
    var title: String {
        switch self {
        case .blackProMist: "Black Pro-Mist"
        case .glimmerglass: "Glimmerglass"
        case .proMist: "Pro-Mist"
        case .cinebloom: "CineBloom"
        }
    }
}

extension OutputGamutCompression {
    /// What each does, then its technical name.
    var title: String {
        switch self {
        case .off: String(localized: "Clipped (off)")
        case .oklch: String(localized: "Gentle (OKLCh)")
        case .oklrab: String(localized: "Gentle, keeping lightness (OKLrab)")
        case .cam16ucs: String(localized: "Perceptual, spektrafilm's (CAM16-UCS)")
        case .acesRGC: String(localized: "Cinema (ACES RGC)")
        }
    }
}

extension InputGamutCompression {
    var title: LocalizedStringResource {
        switch self {
        case .off: "Left as they are (off)"
        case .towardLocus: "Brought toward real colors (xy)"
        }
    }
}

extension SpectralUpsampling {
    /// What each does, then its technical name.
    var title: LocalizedStringResource {
        switch self {
        case .hanatos2025: "Spectral, spektrafilm's (Hanatos 2025)"
        case .arctic2026Alpha: "Memory colors, experimental (Arctic 2026)"
        case .mallett2019: "Fast (Mallett 2019)"
        }
    }
}
