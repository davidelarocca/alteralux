import Foundation

/// A lens of the database, as lensfun describes it.
struct LensRecord: Sendable, Equatable {
    /// The maker's name and its translations; the first is the one to show.
    var makers: [String] = []
    /// The model's name and its translations; the first is the one to show.
    var models: [String] = []
    var mounts: [String] = []
    /// The crop factor of the sensor the calibrations were made on.
    var cropFactor = 1.0
    /// The aspect ratio (width over height) of the pictures the calibrations were made on.
    var aspectRatio = 1.5
    /// The optical center's offset from the middle, in units of half the short side.
    var center = SIMD2<Double>.zero
    var minFocal = 0.0
    var maxFocal = 0.0
    var calibrations = LensCalibrations()

    var displayName: String {
        [makers.first, models.first].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Whether the lens has any correction to give.
    var hasCalibrations: Bool {
        !calibrations.distortion.isEmpty || !calibrations.tca.isEmpty || !calibrations.vignetting.isEmpty
    }
}

/// A camera of the database.
struct CameraRecord: Sendable, Equatable {
    var makers: [String] = []
    var models: [String] = []
    var mount = ""
    var cropFactor = 0.0
}

/// The profile of one lens on one camera: everything lensfun knows of the lens, and the crop
/// factor of the camera it was found for, which sets how the calibrations are rescaled.
public struct LensProfile: Sendable, Equatable {
    /// The lens, maker and model; for the fixed lens of a camera, the camera.
    public let lensName: String
    let lens: LensRecord
    let cameraCropFactor: Double

    /// - Parameter name: what to call the lens instead of the database's own name.
    init(lens: LensRecord, cameraCropFactor: Double, name: String? = nil) {
        lensName = name ?? lens.displayName
        self.lens = lens
        self.cameraCropFactor = cameraCropFactor
    }

    /// The width and height, in millimeters, of a full frame's diagonal: lensfun measures every
    /// sensor against it with the crop factor.
    private static let fullFrameDiagonal = hypot(36.0, 24.0)

    /// The corrections for a photo of `imageWidth` by `imageHeight` pixels, as decoded, taken as
    /// described by `info`; `nil` when the profile has nothing for it (no calibration, a focal
    /// length it does not know, a camera with a sensor too much smaller than the one the lens was
    /// calibrated on).
    ///
    /// The calibrations are interpolated as lensfun does, then rescaled to the photo: pixels are
    /// turned into units of the real focal length with the camera's crop factor and the photo's
    /// size (lensfun's `lfModifier` constructor in `modifier.cpp`), and the terms of each model
    /// from the calibration's sensor to this one (`rescale_polynomial_coefficients` in
    /// `mod-coord.cpp`, `mod-subpix.cpp` and `mod-color.cpp`).
    public func correction(for info: PhotoLensInfo, imageWidth: Int, imageHeight: Int) -> LensCorrection? {
        let focal = info.focalLength
        guard focal > 0, cameraCropFactor > 0.01, imageWidth > 0, imageHeight > 0,
              cameraCropFactor / lens.cropFactor >= LensCalibrations.minimumCropRatio
        else { return nil }

        let distortion = lens.calibrations.distortion(at: focal)
        let realFocal = distortion?.realFocal ?? focal
        guard realFocal > 0 else { return nil }

        // Lensfun measures pixel centers: the picture spans width - 1 by height - 1 of them.
        let spanX = Double(imageWidth >= 2 ? imageWidth - 1 : 1)
        let spanY = Double(imageHeight >= 2 ? imageHeight - 1 : 1)
        let unitsPerPixel = Self.fullFrameDiagonal / cameraCropFactor / hypot(spanX + 1, spanY + 1) / realFocal
        let size = min(spanX, spanY)
        let center = SIMD2(spanX / 2 + size / 2 * lens.center.x, spanY / 2 + size / 2 * lens.center.y)

        // The calibration's own sensor: half its height in millimeters is the unit of the models'
        // radius (half its diagonal for the vignetting), and `realFocal` divided by it is how
        // many of those units a lens unit holds.
        let sensorHalfHeight = Self.fullFrameDiagonal / lens.cropFactor / hypot(lens.aspectRatio, 1) / 2
        let heightScaling = realFocal / sensorHalfHeight
        let sensorHalfDiagonal = Self.fullFrameDiagonal / lens.cropFactor / 2
        let diagonalScaling = realFocal / sensorHalfDiagonal

        let distortionTerms = distortion.map { Self.rescaled($0, scaling: heightScaling) } ?? .zero
        let distortionModel = distortion?.model ?? .none

        let fringing = lens.calibrations.tca(at: focal)
        let fringingTerms = fringing.map { Self.rescaled($0, scaling: heightScaling) }

        let vignettingTerms = vignetting(for: info, scaling: diagonalScaling)

        guard distortionModel != .none || fringingTerms != nil || vignettingTerms != .zero else { return nil }

        let scale = LensCorrection.autoScale(
            model: distortionModel,
            terms: distortionTerms,
            span: SIMD2(spanX, spanY),
            unitsPerPixel: unitsPerPixel,
            hasFringing: fringingTerms != nil,
        )
        return LensCorrection(
            lensName: lensName,
            distortionModel: distortionModel,
            distortionTerms: distortionTerms,
            distortionUnit: 1 / unitsPerPixel,
            center: center,
            tcaModel: fringing?.model ?? .none,
            tcaRed: fringingTerms?.red ?? SIMD3(1, 0, 0),
            tcaBlue: fringingTerms?.blue ?? SIMD3(1, 0, 0),
            vignettingTerms: vignettingTerms,
            vignettingUnit: 1 / unitsPerPixel,
            scale: scale,
        )
    }

    /// The vignetting terms for the photo, in units of the real focal length; zero when the
    /// photo's aperture is unknown or no calibration is near it. A focus distance the photo does
    /// not give is taken as far, 1000 meters, as lensfun's users do.
    private func vignetting(for info: PhotoLensInfo, scaling: Double) -> SIMD3<Double> {
        guard info.aperture > 0 else { return .zero }
        var distance = info.focusDistance ?? 1000
        if !(distance > 0) || distance > 1000 {
            distance = 1000
        }
        let low = min(lens.minFocal, lens.maxFocal)
        let high = max(lens.minFocal, lens.maxFocal)
        guard var terms = lens.calibrations.vignetting(
            focal: info.focalLength, aperture: info.aperture, distance: distance, focalRange: low ... high,
        ) else { return .zero }
        terms.x *= pow(scaling, 2)
        terms.y *= pow(scaling, 4)
        terms.z *= pow(scaling, 6)
        return terms
    }

    /// The distortion terms moved from the calibration's units to lens units (lensfun's
    /// `rescale_polynomial_coefficients`). The `ptlens` and `poly3` models have a `d` that shrinks
    /// the middle of the picture; dividing by its powers enlarges the picture back, so the focal
    /// length stays the real one.
    private static func rescaled(_ calibration: DistortionCalibration, scaling: Double) -> SIMD3<Double> {
        var terms = calibration.terms
        switch calibration.model {
        case .poly3:
            let shrink = 1 - terms.x
            terms.x *= pow(scaling, 2) / pow(shrink, 3)
        case .poly5:
            terms.x *= pow(scaling, 2)
            terms.y *= pow(scaling, 4)
        case .ptlens:
            let shrink = 1 - terms.x - terms.y - terms.z
            terms.x *= pow(scaling, 3) / pow(shrink, 4)
            terms.y *= pow(scaling, 2) / pow(shrink, 3)
            terms.z *= scaling / pow(shrink, 2)
        case .none:
            break
        }
        return terms
    }

    /// The fringing terms of the red and the blue channel as `(v, c, b)`, moved to lens units.
    private static func rescaled(_ calibration: TCACalibration, scaling: Double) -> (red: SIMD3<Double>, blue: SIMD3<Double>) {
        let terms = calibration.terms
        switch calibration.model {
        case .poly3:
            return (
                SIMD3(terms[0], terms[2] * scaling, terms[4] * scaling * scaling),
                SIMD3(terms[1], terms[3] * scaling, terms[5] * scaling * scaling),
            )
        case .linear, .none:
            return (SIMD3(terms[0], 0, 0), SIMD3(terms[1], 0, 0))
        }
    }
}
