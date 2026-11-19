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
        exposureEV: Double = 0,
        autoExposure: Bool = true,
        filmFormatMM: Double = 35,
        printExposure: Double = 1,
        yellowFilterShift: Double = 0,
        magentaFilterShift: Double = 0,
        preflashExposure: Double = 0,
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
        self.exposureEV = exposureEV
        self.autoExposure = autoExposure
        self.filmFormatMM = filmFormatMM
        self.printExposure = printExposure
        self.yellowFilterShift = yellowFilterShift
        self.magentaFilterShift = magentaFilterShift
        self.preflashExposure = preflashExposure
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
        if let advancedJSON, !advancedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard
                let advanced = try JSONSerialization.jsonObject(with: Data(advancedJSON.utf8)) as? [String: Any]
            else {
                throw SpektrafilmError.invalidAdvancedParameters
            }
            patch = Self.deepMerge(patch, advanced)
        }
        let data = try JSONSerialization.data(withJSONObject: patch, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw SpektrafilmError.invalidAdvancedParameters
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
