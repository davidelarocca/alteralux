import Foundation

/// Everything the user can adjust for one photo.
///
/// This is the app's own, stable model of an edit. It is saved with the photo
/// and converted to the engine's parameter JSON by ``enginePatchJSON()``.
/// Only the controls the app exposes live here; every other engine parameter
/// keeps its default, unless overridden through ``advancedJSON``.
public struct DevelopSettings: Codable, Equatable, Sendable {
    // MARK: Materials

    /// Film stock id, e.g. `kodak_portra_400`.
    public var filmID: String
    /// Print paper id, e.g. `kodak_portra_endura`. Unused when ``scanFilm`` is set.
    public var paperID: String
    /// Scan the film directly instead of printing it. The normal choice for
    /// slide film; on a negative it shows the orange-masked negative itself.
    public var scanFilm: Bool

    // MARK: Before the film

    /// The temperature of the light the RAW decoder takes as neutral, in kelvin. `nil` leaves
    /// what the camera recorded, whatever the photo.
    public var temperature: Double?
    /// The tint that goes with ``temperature``. `nil` leaves what the camera recorded.
    public var tint: Double?

    // MARK: Camera

    /// Exposure compensation in stops, on top of the metered exposure.
    public var exposureEV: Double
    /// Meter the scene automatically (center-weighted), like a camera would.
    public var autoExposure: Bool
    /// Width of the film frame in millimetres. Smaller formats show more grain
    /// and larger halation for the same picture.
    public var filmFormatMM: Double

    // MARK: Enlarger

    /// Print exposure multiplier (1 = normal).
    public var printExposure: Double
    /// Yellow filter shift from the neutral setting, in filter units.
    public var yellowFilterShift: Double
    /// Magenta filter shift from the neutral setting, in filter units.
    public var magentaFilterShift: Double
    /// Pre-flash exposure of the paper, to hold highlight detail (0 = off).
    public var preflashExposure: Double

    // MARK: Development

    /// How long the film is developed, in minutes, for the black and white films that were
    /// measured at several times. `nil` takes the middle one; the engine takes the time
    /// measured nearest to the one asked.
    public var filmDevelopmentTime: Double?
    /// How long the paper is developed, in minutes, for the black and white papers measured
    /// at several times. `nil` takes the middle one.
    public var printDevelopmentTime: Double?

    // MARK: Film character

    public var grainEnabled: Bool
    /// Area of the silver halide particles in µm² (bigger = coarser grain).
    public var grainParticleArea: Double
    public var halationEnabled: Bool
    /// Strength of the red halo around bright lights (1 = as measured).
    public var halationAmount: Double
    /// Strength of light scattering inside the emulsion (1 = as measured).
    public var scatterAmount: Double
    /// Inter-layer development effects that give film its color separation.
    public var couplersEnabled: Bool
    public var couplersAmount: Double

    // MARK: Scanner

    /// Unsharp mask radius in pixels (0 = off).
    public var sharpenRadius: Double
    public var sharpenAmount: Double

    // MARK: Advanced

    /// Optional raw engine parameter JSON, merged over everything above.
    /// See the engine's default parameter tree for the available keys.
    public var advancedJSON: String?

    public init(
        filmID: String = "kodak_portra_400",
        paperID: String = "kodak_portra_endura",
        scanFilm: Bool = false,
        temperature: Double? = nil,
        tint: Double? = nil,
        exposureEV: Double = 0,
        autoExposure: Bool = true,
        filmFormatMM: Double = 35,
        printExposure: Double = 1,
        yellowFilterShift: Double = 0,
        magentaFilterShift: Double = 0,
        preflashExposure: Double = 0,
        filmDevelopmentTime: Double? = nil,
        printDevelopmentTime: Double? = nil,
        grainEnabled: Bool = true,
        grainParticleArea: Double = 0.2,
        halationEnabled: Bool = true,
        halationAmount: Double = 1,
        scatterAmount: Double = 1,
        couplersEnabled: Bool = true,
        couplersAmount: Double = 1,
        sharpenRadius: Double = 0.7,
        sharpenAmount: Double = 0.7,
        advancedJSON: String? = nil,
    ) {
        self.filmID = filmID
        self.paperID = paperID
        self.scanFilm = scanFilm
        self.temperature = temperature
        self.tint = tint
        self.exposureEV = exposureEV
        self.autoExposure = autoExposure
        self.filmFormatMM = filmFormatMM
        self.printExposure = printExposure
        self.yellowFilterShift = yellowFilterShift
        self.magentaFilterShift = magentaFilterShift
        self.preflashExposure = preflashExposure
        self.filmDevelopmentTime = filmDevelopmentTime
        self.printDevelopmentTime = printDevelopmentTime
        self.grainEnabled = grainEnabled
        self.grainParticleArea = grainParticleArea
        self.halationEnabled = halationEnabled
        self.halationAmount = halationAmount
        self.scatterAmount = scatterAmount
        self.couplersEnabled = couplersEnabled
        self.couplersAmount = couplersAmount
        self.sharpenRadius = sharpenRadius
        self.sharpenAmount = sharpenAmount
        self.advancedJSON = advancedJSON
    }
}

// MARK: - Decoding

public extension DevelopSettings {
    /// Reads settings saved by any version of the app: a value that was not saved, because the
    /// version that wrote them did not have it yet, takes its default.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DevelopSettings()
        filmID = try values.decodeIfPresent(String.self, forKey: .filmID) ?? defaults.filmID
        paperID = try values.decodeIfPresent(String.self, forKey: .paperID) ?? defaults.paperID
        scanFilm = try values.decodeIfPresent(Bool.self, forKey: .scanFilm) ?? defaults.scanFilm
        temperature = try values.decodeIfPresent(Double.self, forKey: .temperature)
        tint = try values.decodeIfPresent(Double.self, forKey: .tint)
        exposureEV = try values.decodeIfPresent(Double.self, forKey: .exposureEV) ?? defaults.exposureEV
        autoExposure = try values.decodeIfPresent(Bool.self, forKey: .autoExposure) ?? defaults.autoExposure
        filmFormatMM = try values.decodeIfPresent(Double.self, forKey: .filmFormatMM) ?? defaults.filmFormatMM
        printExposure = try values.decodeIfPresent(Double.self, forKey: .printExposure) ?? defaults.printExposure
        yellowFilterShift = try values.decodeIfPresent(Double.self, forKey: .yellowFilterShift) ?? defaults.yellowFilterShift
        magentaFilterShift = try values.decodeIfPresent(Double.self, forKey: .magentaFilterShift) ?? defaults.magentaFilterShift
        preflashExposure = try values.decodeIfPresent(Double.self, forKey: .preflashExposure) ?? defaults.preflashExposure
        filmDevelopmentTime = try values.decodeIfPresent(Double.self, forKey: .filmDevelopmentTime)
        printDevelopmentTime = try values.decodeIfPresent(Double.self, forKey: .printDevelopmentTime)
        grainEnabled = try values.decodeIfPresent(Bool.self, forKey: .grainEnabled) ?? defaults.grainEnabled
        grainParticleArea = try values.decodeIfPresent(Double.self, forKey: .grainParticleArea) ?? defaults.grainParticleArea
        halationEnabled = try values.decodeIfPresent(Bool.self, forKey: .halationEnabled) ?? defaults.halationEnabled
        halationAmount = try values.decodeIfPresent(Double.self, forKey: .halationAmount) ?? defaults.halationAmount
        scatterAmount = try values.decodeIfPresent(Double.self, forKey: .scatterAmount) ?? defaults.scatterAmount
        couplersEnabled = try values.decodeIfPresent(Bool.self, forKey: .couplersEnabled) ?? defaults.couplersEnabled
        couplersAmount = try values.decodeIfPresent(Double.self, forKey: .couplersAmount) ?? defaults.couplersAmount
        sharpenRadius = try values.decodeIfPresent(Double.self, forKey: .sharpenRadius) ?? defaults.sharpenRadius
        sharpenAmount = try values.decodeIfPresent(Double.self, forKey: .sharpenAmount) ?? defaults.sharpenAmount
        advancedJSON = try values.decodeIfPresent(String.self, forKey: .advancedJSON)
    }
}

// MARK: - White balance

public extension DevelopSettings {
    /// The white balance to decode a RAW with: the values chosen here, over the ones the
    /// camera recorded.
    func whiteBalance(asShot: WhiteBalance) -> WhiteBalance {
        WhiteBalance(temperature: temperature ?? asShot.temperature, tint: tint ?? asShot.tint)
    }
}

// MARK: - Engine parameters

extension DevelopSettings {
    /// The engine parameter patch for these settings, as JSON.
    ///
    /// The engine deep-merges it over its defaults and rejects unknown keys,
    /// so a mismatch with an updated engine fails loudly (and in the tests).
    public func enginePatchJSON() throws -> String {
        var patch: [String: Any] = [
            "camera": [
                "exposure_compensation_ev": exposureEV,
                "auto_exposure": autoExposure,
                "film_format_mm": filmFormatMM,
            ],
            "enlarger": [
                "print_exposure": printExposure,
                "y_filter_shift": yellowFilterShift,
                "m_filter_shift": magentaFilterShift,
                "preflash_exposure": preflashExposure,
            ],
            "film_render": [
                "grain": [
                    "active": grainEnabled,
                    "agx_particle_area_um2": grainParticleArea,
                ],
                "halation": [
                    "active": halationEnabled,
                    "halation_amount": halationAmount,
                    "scatter_amount": scatterAmount,
                ],
                "dir_couplers": [
                    "active": couplersEnabled,
                    "amount": couplersAmount,
                ],
            ],
            "scanner": [
                "unsharp_mask": [sharpenRadius, sharpenAmount],
            ],
            "io": [
                "scan_film": scanFilm,
            ],
        ]
        if let filmDevelopmentTime, var film = patch["film_render"] as? [String: Any] {
            film["development_time"] = filmDevelopmentTime
            patch["film_render"] = film
        }
        if let printDevelopmentTime {
            patch["print_render"] = ["development_time": printDevelopmentTime]
        }
        if let advancedJSON, !advancedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard
                let advanced = try JSONSerialization.jsonObject(with: Data(advancedJSON.utf8)) as? [String: Any]
            else {
                throw AlteraluxError.invalidAdvancedParameters
            }
            patch = Self.deepMerge(patch, advanced)
        }
        let data = try JSONSerialization.data(withJSONObject: patch, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw AlteraluxError.invalidAdvancedParameters
        }
        return json
    }

    private static func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let baseChild = result[key] as? [String: Any], let overlayChild = value as? [String: Any] {
                result[key] = deepMerge(baseChild, overlayChild)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
