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

/// The shot's details: how the scene is metered, the lens's softness and the diffusion filter.
struct ShotDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        WindowPopUp(
            "Metering", selection: $settings.meteringMethod,
            options: MeteringMethod.allCases.map { WindowPopUpOption($0, title: String(localized: $0.title)) },
        )
        .disabled(!settings.autoExposure)
        .help("How the automatic metering weighs the scene.")
        ParameterSlider("Lens softness", value: $settings.lensBlur, in: 0 ... 100, step: 1, fractionDigits: 0)
            .help("Blurs the image on the film, in micrometres, as a soft lens would.")
        DiffusionDetails(filter: $settings.diffusionFilter)
    }
}

private struct DiffusionDetails: View {
    @Binding var filter: DiffusionFilterSettings

    var body: some View {
        Group {
            WindowPopUp(
                "Kind of filter", selection: $filter.family,
                options: DiffusionFamily.allCases.map { WindowPopUpOption($0, title: $0.title) },
            )
            ParameterSlider("Filter scale", value: $filter.spatialScale, in: 0.1 ... 3, defaultValue: 1)
            ParameterSlider("Glow", value: $filter.haloIntensity, in: 0 ... 2, defaultValue: 1)
            ParameterSlider("Glow size", value: $filter.haloSize, in: 0.1 ... 3, defaultValue: 1)
            ParameterSlider("Glow warmth", value: $filter.haloWarmth, in: -1.5 ... 1.5, showsSign: true)
            ParameterSlider("Core", value: $filter.coreIntensity, in: 0 ... 2, defaultValue: 1)
            ParameterSlider("Core size", value: $filter.coreSize, in: 0.1 ... 3, defaultValue: 1)
            ParameterSlider("Bloom", value: $filter.bloomIntensity, in: 0 ... 2, defaultValue: 1)
            ParameterSlider("Bloom size", value: $filter.bloomSize, in: 0.1 ... 3, defaultValue: 1)
        }
        .disabled(!filter.enabled)
    }
}

/// The film's details: the grain's softness and layers, the halation and scatter, the couplers'
/// spread.
struct FilmDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        ParameterSlider("Grain softness", value: $settings.grainDetail.blur, in: 0 ... 3, defaultValue: 0.65)
            .disabled(!settings.grainEnabled)
        ParameterSlider(
            "Grain layers", value: whole($settings.grainDetail.subLayers), in: 1 ... 4,
            step: 1, defaultValue: 1, fractionDigits: 0,
        )
        .disabled(!settings.grainEnabled)
        HalationDetails(settings: $settings)
        Group {
            ParameterSlider(
                "Couplers' reach", value: $settings.couplersDetail.diffusionSize, in: 0 ... 100,
                step: 1, defaultValue: 20, fractionDigits: 0,
            )
            ParameterSlider(
                "Couplers' tail", value: $settings.couplersDetail.diffusionTail, in: 0 ... 400,
                step: 5, defaultValue: 200, fractionDigits: 0,
            )
            ParameterSlider("Tail weight", value: $settings.couplersDetail.tailWeight, in: 0 ... 1, defaultValue: 0.06)
        }
        .disabled(!settings.couplersEnabled)
    }
}

private struct HalationDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        Group {
            ParameterSlider("Halation size", value: $settings.halationDetail.halationScale, in: 0.1 ... 5, defaultValue: 1)
            ParameterSlider("Scatter", value: $settings.scatterAmount, in: 0 ... 3, defaultValue: 1)
                .help("Light spreading inside the emulsion, which softens fine detail.")
            ParameterSlider("Scatter size", value: $settings.halationDetail.scatterScale, in: 0.1 ... 5, defaultValue: 1)
            ParameterSlider(
                "Bounces", value: whole($settings.halationDetail.bounces), in: 1 ... 5,
                step: 1, defaultValue: 3, fractionDigits: 0,
            )
            .help("How many times light bounces off the back of the film.")
            ParameterSlider("Bounce decay", value: $settings.halationDetail.bounceDecay, in: 0 ... 1, defaultValue: 0.5)
            Toggle("Keep the halation's light", isOn: $settings.halationDetail.renormalize)
                .help("The light the halo spreads is taken from the light that made it.")
        }
        .disabled(!settings.halationEnabled)
    }
}

/// The print's details: the pre-flash's filters, the glare and the paper's curves rebuilt.
struct PrintDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        Group {
            ParameterSlider(
                "Pre-flash yellow", value: $settings.preflashYellowShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true,
            )
            ParameterSlider(
                "Pre-flash magenta", value: $settings.preflashMagentaShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true,
            )
        }
        .disabled(settings.preflashExposure == 0)
        ParameterSlider(
            "Glare", value: $settings.printGlare.percent, in: 0 ... 0.2, step: 0.005,
            defaultValue: 0.03, fractionDigits: 3, isOn: $settings.printGlare.enabled,
        )
        .help("Stray light in the enlarger and on the paper, which veils the shadows.")
        Group {
            ParameterSlider("Glare roughness", value: $settings.printGlare.roughness, in: 0 ... 2, defaultValue: 0.7)
            ParameterSlider("Glare softness", value: $settings.printGlare.blur, in: 0 ... 5, defaultValue: 0.5)
        }
        .disabled(!settings.printGlare.enabled)
        PrintCurvesDetails(curves: $settings.printCurves)
    }
}

private struct PrintCurvesDetails: View {
    @Binding var curves: PrintCurvesSettings

    var body: some View {
        Toggle("Rebuild the paper's curves", isOn: $curves.enabled)
            .help("Rebuilds the paper's response from its model, so its contrast can be changed.")
        if curves.enabled {
            ParameterSlider("Contrast", value: $curves.gamma, in: 0.5 ... 2, defaultValue: 1)
            ParameterSlider("Contrast of the fast layer", value: $curves.gammaFast, in: 0.5 ... 2, defaultValue: 1)
            ParameterSlider("Contrast of the slow layer", value: $curves.gammaSlow, in: 0.5 ... 2, defaultValue: 1)
            ParameterSlider("Red contrast", value: $curves.gammaRed, in: 0.5 ... 2, defaultValue: 1)
            ParameterSlider("Green contrast", value: $curves.gammaGreen, in: 0.5 ... 2, defaultValue: 1)
            ParameterSlider("Blue contrast", value: $curves.gammaBlue, in: 0.5 ... 2, defaultValue: 1)
            ParameterSlider("Exhausted developer", value: $curves.developerExhaustion, in: 0 ... 1)
        }
    }
}

/// The scan's details: the sharpening's radius, the scanner's lens, its white and black points, and
/// how colors enter the film and leave the scan.
struct ScanDetails: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        ParameterSlider("Sharpening radius", value: $settings.sharpenRadius, in: 0 ... 3, defaultValue: 0.7)
        ParameterSlider("Scanner softness", value: $settings.scanner.lensBlur, in: 0 ... 5)
        Toggle("Correct the white", isOn: $settings.scanner.correctsWhite)
        if settings.scanner.correctsWhite {
            ParameterSlider("White level", value: $settings.scanner.whiteLevel, in: 0.5 ... 1, defaultValue: 0.98)
        }
        Toggle("Correct the black", isOn: $settings.scanner.correctsBlack)
        if settings.scanner.correctsBlack {
            ParameterSlider("Black level", value: $settings.scanner.blackLevel, in: 0 ... 0.5, defaultValue: 0.01)
        }
        ColorDetails(color: $settings.color)
    }
}

private struct ColorDetails: View {
    @Binding var color: ColorSettings

    var body: some View {
        WindowPopUp(
            "Gamut compression", selection: $color.outputGamut,
            options: OutputGamutCompression.allCases.map { WindowPopUpOption($0, title: $0.title) },
        )
        .help("How colors the screen cannot show are brought inside it.")
        WindowPopUp(
            "Input gamut compression", selection: $color.inputGamut,
            options: InputGamutCompression.allCases.map { WindowPopUpOption($0, title: String(localized: $0.title)) },
        )
        Toggle("CAT16 adaptation", isOn: $color.cat16)
            .help("Adapts the photo's colors to the film's light with CAT16 rather than CAT02.")
        WindowPopUp(
            "Spectral upsampling", selection: $color.upsampling,
            options: SpectralUpsampling.allCases.map { WindowPopUpOption($0, title: $0.title) },
        )
        .help("How the photo's colors become the light that reaches the film's layers.")
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
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .oklch: "OKLCh"
        case .oklrab: "OKLrab"
        case .cam16ucs: "CAM16-UCS"
        case .acesRGC: "ACES RGC"
        }
    }
}

extension InputGamutCompression {
    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .towardLocus: "Toward the spectral locus"
        }
    }
}

extension SpectralUpsampling {
    /// The methods' own names.
    var title: String {
        switch self {
        case .hanatos2025: "Hanatos 2025"
        case .arctic2026Alpha: "Arctic 2026 (alpha)"
        case .mallett2019: "Mallett 2019"
        }
    }
}
