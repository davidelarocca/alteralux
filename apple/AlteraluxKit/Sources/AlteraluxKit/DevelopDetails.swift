import Foundation

// The controls spektrafilm offers beyond the main ones (ADR 0016): each group starts from the
// engine's own defaults, and settings saved before a value existed read it as that default, so a
// photo developed earlier keeps its look.

/// How the camera meters the scene when the exposure is automatic.
public enum MeteringMethod: String, Codable, CaseIterable, Sendable {
    case average
    case median
    case centerWeighted = "center_weighted"
    case partial
    case matrix
    case multiZone = "multi_zone"
    case highlightWeighted = "highlight_weighted"
}

/// The kind of diffusion filter in front of the lens.
public enum DiffusionFamily: String, Codable, CaseIterable, Sendable {
    case blackProMist = "black_pro_mist"
    case glimmerglass
    case proMist = "pro_mist"
    case cinebloom
}

/// How the colors out of the film are brought inside the display's gamut.
public enum OutputGamutCompression: String, Codable, CaseIterable, Sendable {
    case off
    case oklch
    case oklrab
    case cam16ucs
    case acesRGC = "aces_rgc"
}

/// How the colors of the photo are brought inside what the film can see.
public enum InputGamutCompression: String, Codable, CaseIterable, Sendable {
    case off
    /// Toward the spectral locus, on the chromaticity diagram.
    case towardLocus = "xy"
}

/// How the photo's colors become the light that reaches the film's layers.
public enum SpectralUpsampling: String, Codable, CaseIterable, Sendable {
    case hanatos2025
    case arctic2026Alpha = "arctic2026alpha02"
    case mallett2019
}

/// A diffusion filter in front of the lens: a core of glow, a halo and a bloom around the lights.
public struct DiffusionFilterSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var family = DiffusionFamily.blackProMist
    public var strength = 0.5
    public var spatialScale = 1.0
    /// From cool (negative) to warm (positive).
    public var haloWarmth = 0.0
    public var coreIntensity = 1.0
    public var coreSize = 1.0
    public var haloIntensity = 1.0
    public var haloSize = 1.0
    public var bloomIntensity = 1.0
    public var bloomSize = 1.0

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        enabled = try values.value(.enabled, or: defaults.enabled)
        family = try values.value(.family, or: defaults.family)
        strength = try values.value(.strength, or: defaults.strength)
        spatialScale = try values.value(.spatialScale, or: defaults.spatialScale)
        haloWarmth = try values.value(.haloWarmth, or: defaults.haloWarmth)
        coreIntensity = try values.value(.coreIntensity, or: defaults.coreIntensity)
        coreSize = try values.value(.coreSize, or: defaults.coreSize)
        haloIntensity = try values.value(.haloIntensity, or: defaults.haloIntensity)
        haloSize = try values.value(.haloSize, or: defaults.haloSize)
        bloomIntensity = try values.value(.bloomIntensity, or: defaults.bloomIntensity)
        bloomSize = try values.value(.bloomSize, or: defaults.bloomSize)
    }

    var enginePatch: [String: Any] {
        [
            "active": enabled, "filter_family": family.rawValue, "strength": strength,
            "spatial_scale": spatialScale, "halo_warmth": haloWarmth, "core_intensity": coreIntensity,
            "core_size": coreSize, "halo_intensity": haloIntensity, "halo_size": haloSize,
            "bloom_intensity": bloomIntensity, "bloom_size": bloomSize,
        ]
    }
}

/// The film's grain beyond its size: how soft it is and in how many sub-layers it forms.
public struct GrainDetail: Codable, Equatable, Sendable {
    /// The blur after the grain is formed, in pixels.
    public var blur = 0.65
    public var subLayers = 1

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        blur = try values.value(.blur, or: defaults.blur)
        subLayers = try values.value(.subLayers, or: defaults.subLayers)
    }
}

/// The halation and the light scattered inside the emulsion, beyond their amounts.
public struct HalationDetail: Codable, Equatable, Sendable {
    public var halationScale = 1.0
    public var scatterScale = 1.0
    /// How many times light bounces off the film's back.
    public var bounces = 3
    /// How much of the light each bounce keeps.
    public var bounceDecay = 0.5
    public var renormalize = true

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        halationScale = try values.value(.halationScale, or: defaults.halationScale)
        scatterScale = try values.value(.scatterScale, or: defaults.scatterScale)
        bounces = try values.value(.bounces, or: defaults.bounces)
        bounceDecay = try values.value(.bounceDecay, or: defaults.bounceDecay)
        renormalize = try values.value(.renormalize, or: defaults.renormalize)
    }
}

/// How far the development inhibitors (DIR couplers) spread between the film's layers.
public struct CouplersDetail: Codable, Equatable, Sendable {
    /// In µm.
    public var diffusionSize = 20.0
    /// In µm.
    public var diffusionTail = 200.0
    public var tailWeight = 0.06

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        diffusionSize = try values.value(.diffusionSize, or: defaults.diffusionSize)
        diffusionTail = try values.value(.diffusionTail, or: defaults.diffusionTail)
        tailWeight = try values.value(.tailWeight, or: defaults.tailWeight)
    }
}

/// Light that veils the print: stray light in the enlarger and on the paper.
public struct GlareSettings: Codable, Equatable, Sendable {
    public var enabled = true
    /// The share of the light that is stray, as a fraction.
    public var percent = 0.03
    public var roughness = 0.7
    /// In pixels.
    public var blur = 0.5

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        enabled = try values.value(.enabled, or: defaults.enabled)
        percent = try values.value(.percent, or: defaults.percent)
        roughness = try values.value(.roughness, or: defaults.roughness)
        blur = try values.value(.blur, or: defaults.blur)
    }

    var enginePatch: [String: Any] {
        ["active": enabled, "percent": percent, "roughness": roughness, "blur": blur]
    }
}

/// The paper's density curves rebuilt from its model, with their contrast changed overall, in the
/// fast and slow emulsions, per color, and with an exhausted developer.
public struct PrintCurvesSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var gamma = 1.0
    public var gammaFast = 1.0
    public var gammaSlow = 1.0
    public var gammaRed = 1.0
    public var gammaGreen = 1.0
    public var gammaBlue = 1.0
    public var developerExhaustion = 0.0

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        enabled = try values.value(.enabled, or: defaults.enabled)
        gamma = try values.value(.gamma, or: defaults.gamma)
        gammaFast = try values.value(.gammaFast, or: defaults.gammaFast)
        gammaSlow = try values.value(.gammaSlow, or: defaults.gammaSlow)
        gammaRed = try values.value(.gammaRed, or: defaults.gammaRed)
        gammaGreen = try values.value(.gammaGreen, or: defaults.gammaGreen)
        gammaBlue = try values.value(.gammaBlue, or: defaults.gammaBlue)
        developerExhaustion = try values.value(.developerExhaustion, or: defaults.developerExhaustion)
    }

    var enginePatch: [String: Any] {
        [
            "active": enabled, "gamma_factor": gamma, "gamma_factor_fast": gammaFast,
            "gamma_factor_slow": gammaSlow, "gamma_factor_red": gammaRed, "gamma_factor_green": gammaGreen,
            "gamma_factor_blue": gammaBlue, "developer_exhaustion": developerExhaustion,
        ]
    }
}

/// The scanner beyond its sharpening: its lens's softness and where it sets white and black.
public struct ScannerDetail: Codable, Equatable, Sendable {
    /// In pixels.
    public var lensBlur = 0.0
    public var correctsWhite = false
    public var whiteLevel = 0.98
    public var correctsBlack = false
    public var blackLevel = 0.01

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        lensBlur = try values.value(.lensBlur, or: defaults.lensBlur)
        correctsWhite = try values.value(.correctsWhite, or: defaults.correctsWhite)
        whiteLevel = try values.value(.whiteLevel, or: defaults.whiteLevel)
        correctsBlack = try values.value(.correctsBlack, or: defaults.correctsBlack)
        blackLevel = try values.value(.blackLevel, or: defaults.blackLevel)
    }
}

/// How colors enter the film and leave the scan.
public struct ColorSettings: Codable, Equatable, Sendable {
    public var outputGamut = OutputGamutCompression.cam16ucs
    public var inputGamut = InputGamutCompression.towardLocus
    /// CAT16 rather than CAT02 for the input's chromatic adaptation.
    public var cat16 = true
    public var upsampling = SpectralUpsampling.hanatos2025

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        outputGamut = try values.value(.outputGamut, or: defaults.outputGamut)
        inputGamut = try values.value(.inputGamut, or: defaults.inputGamut)
        cat16 = try values.value(.cat16, or: defaults.cat16)
        upsampling = try values.value(.upsampling, or: defaults.upsampling)
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `defaultValue` when the settings were saved without it.
    func value<T: Decodable>(_ key: Key, or defaultValue: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue
    }
}
