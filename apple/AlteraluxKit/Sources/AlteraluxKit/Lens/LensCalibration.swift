import Foundation

/// The models lensfun describes lens distortion with. The model says how the terms are read.
public enum LensDistortionModel: Sendable, Equatable {
    /// No distortion correction.
    case none
    /// `Rd = Ru * (1 + k1 * Ru^2)`
    case poly3
    /// `Rd = Ru * (1 + k1 * Ru^2 + k2 * Ru^4)`
    case poly5
    /// `Rd = Ru * (a * Ru^3 + b * Ru^2 + c * Ru + 1)`
    case ptlens
}

/// The models lensfun describes lateral color fringing (TCA) with.
public enum LensTCAModel: Sendable, Equatable {
    /// No fringing correction.
    case none
    /// `Rd = Ru * k` for the red and for the blue channel.
    case linear
    /// `Rd = Ru * (b * Ru^2 + c * Ru + v)` for the red and for the blue channel.
    case poly3
}

/// One distortion calibration of a lens: the terms measured at one focal length.
struct DistortionCalibration: Sendable, Equatable {
    var model: LensDistortionModel
    var focal: Double
    /// The focal length the picture really has at this setting, which lensfun uses as the unit of
    /// its coordinates. The nominal focal length when nothing better is known.
    var realFocal: Double
    /// `k1`, `k1 k2` or `a b c`, as the model reads them.
    var terms: SIMD3<Double>
}

/// One lateral color calibration of a lens at one focal length.
struct TCACalibration: Sendable, Equatable {
    var model: LensTCAModel
    var focal: Double
    /// The six terms in lensfun's order: red and blue of `v` (or `k`), of `c` and of `b`.
    var terms: [Double]
}

/// One vignetting calibration of a lens at one focal length, aperture and focus distance.
struct VignettingCalibration: Sendable, Equatable {
    var focal: Double
    var aperture: Double
    /// In meters.
    var distance: Double
    /// `k1 k2 k3` of the model `1 / (1 + k1 r^2 + k2 r^4 + k3 r^6)`.
    var terms: SIMD3<Double>
}

/// The calibrations of a lens and how lensfun interpolates them for a photo, from lensfun's
/// `lens.cpp` (`InterpolateDistortion`, `InterpolateTCA`, `InterpolateVignetting`).
struct LensCalibrations: Sendable, Equatable {
    var distortion: [DistortionCalibration] = []
    var tca: [TCACalibration] = []
    var vignetting: [VignettingCalibration] = []

    /// The smallest ratio between a camera's crop factor and a calibration's that lensfun accepts:
    /// a calibration made on a sensor slightly smaller than the camera's is still used.
    static let minimumCropRatio = 0.96

    /// The vignetting weights follow inverse distance weighting with this power.
    private static let vignettingPower = 3.5

    // MARK: Distortion

    /// The distortion at `focal`: the calibration made there, or a spline through the nearest ones
    /// (the terms are multiplied by the focal length first, since they follow a 1/f law).
    func distortion(at focal: Double) -> DistortionCalibration? {
        let usable = firstModel(distortion.filter { $0.model != .none }) { $0.model }
        var spline = Spline<DistortionCalibration>()
        for calibration in usable {
            let delta = focal - calibration.focal
            if delta == 0 {
                return calibration
            }
            spline.insert(calibration, delta: delta)
        }
        guard let lower = spline.entries[1], let upper = spline.entries[2] else {
            return spline.entries[1] ?? spline.entries[2]
        }
        let fraction = (focal - lower.focal) / (upper.focal - lower.focal)
        let realFocal = Self.hermite(
            spline.entries[0]?.realFocal, lower.realFocal, upper.realFocal, spline.entries[3]?.realFocal, fraction,
        )
        var terms = SIMD3<Double>.zero
        for index in 0 ..< 3 {
            terms[index] = Self.hermite(
                spline.entries[0].map { $0.terms[index] * $0.focal },
                lower.terms[index] * lower.focal,
                upper.terms[index] * upper.focal,
                spline.entries[3].map { $0.terms[index] * $0.focal },
                fraction,
            ) / focal
        }
        return DistortionCalibration(model: lower.model, focal: focal, realFocal: realFocal, terms: terms)
    }

    // MARK: TCA

    /// The lateral color calibration at `focal`, found as the distortion is. The terms after the
    /// first two (the `c` and `b` of the polynomial) follow the 1/f law and are scaled by it.
    func tca(at focal: Double) -> TCACalibration? {
        let usable = firstModel(tca.filter { $0.model != .none }) { $0.model }
        var spline = Spline<TCACalibration>()
        for calibration in usable {
            let delta = focal - calibration.focal
            if delta == 0 {
                return calibration
            }
            spline.insert(calibration, delta: delta)
        }
        guard let lower = spline.entries[1], let upper = spline.entries[2] else {
            return spline.entries[1] ?? spline.entries[2]
        }
        let fraction = (focal - lower.focal) / (upper.focal - lower.focal)
        var terms = [Double](repeating: 0, count: 6)
        for index in 0 ..< 6 {
            let scaled: (TCACalibration) -> Double = { calibration in
                calibration.terms[index] * (index < 2 ? 1 : calibration.focal)
            }
            terms[index] = Self.hermite(
                spline.entries[0].map(scaled), scaled(lower), scaled(upper), spline.entries[3].map(scaled), fraction,
            ) / (index < 2 ? 1 : focal)
        }
        return TCACalibration(model: lower.model, focal: focal, terms: terms)
    }

    // MARK: Vignetting

    /// The vignetting at a focal length, aperture and focus distance: the calibration made there,
    /// or an inverse distance weighted mean of all of them, the distance measured on the focal
    /// length (as a share of the lens's range), the reciprocal of the aperture and of the
    /// focus distance. `nil` when no calibration is near enough (a distance above 1).
    func vignetting(focal: Double, aperture: Double, distance: Double, focalRange: ClosedRange<Double>) -> SIMD3<Double>? {
        var total = SIMD3<Double>.zero
        var totalWeight = 0.0
        var smallest = Double.greatestFiniteMagnitude
        for calibration in vignetting {
            let gap = Self.vignettingDistance(
                calibration, focal: focal, aperture: aperture, distance: distance, focalRange: focalRange,
            )
            if gap < 0.0001 {
                return calibration.terms
            }
            smallest = min(smallest, gap)
            let weight = abs(1 / pow(gap, Self.vignettingPower))
            total += weight * calibration.terms
            totalWeight += weight
        }
        guard smallest <= 1, totalWeight > 0, smallest < Double.greatestFiniteMagnitude else { return nil }
        return total / totalWeight
    }

    private static func vignettingDistance(
        _ calibration: VignettingCalibration,
        focal: Double,
        aperture: Double,
        distance: Double,
        focalRange: ClosedRange<Double>,
    ) -> Double {
        var focalA = focal - focalRange.lowerBound
        var focalB = calibration.focal - focalRange.lowerBound
        let span = focalRange.upperBound - focalRange.lowerBound
        if span != 0 {
            focalA /= span
            focalB /= span
        }
        let apertureA = 4 / aperture
        let apertureB = 4 / calibration.aperture
        let distanceA = 0.1 / distance
        let distanceB = 0.1 / calibration.distance
        let gap = (focalB - focalA) * (focalB - focalA)
            + (apertureB - apertureA) * (apertureB - apertureA)
            + (distanceB - distanceA) * (distanceB - distanceA)
        return gap.squareRoot()
    }

    // MARK: Helpers

    /// The calibrations that share the model of the first one: lensfun reads the first model it
    /// meets and ignores entries of any other.
    private func firstModel<Entry>(_ entries: [Entry], model: (Entry) -> some Equatable) -> [Entry] {
        guard let first = entries.first else { return [] }
        return entries.filter { model($0) == model(first) }
    }

    /// Lensfun's cubic Hermite interpolation between `second` and `third` at `fraction`, with tangents
    /// from the neighbors `first` and `fourth` when there are some and from the chord when not.
    static func hermite(_ first: Double?, _ second: Double, _ third: Double, _ fourth: Double?, _ fraction: Double) -> Double {
        let tangentSecond = first.map { (third - $0) * 0.5 } ?? third - second
        let tangentThird = fourth.map { ($0 - second) * 0.5 } ?? third - second
        let square = fraction * fraction
        let cube = square * fraction
        return (2 * cube - 3 * square + 1) * second
            + (cube - 2 * square + fraction) * tangentSecond
            + (-2 * cube + 3 * square) * third
            + (cube - square) * tangentThird
    }
}

/// The four calibrations nearest to a focal length, as lensfun keeps them (`__insert_spline`):
/// indexes 1 and 0 are the two nearest calibrations with a longer focal length (1 the nearest),
/// indexes 2 and 3 the two nearest with the same or a shorter one (2 the nearest). The
/// interpolation runs from index 1 to index 2, the others giving the slopes at its ends.
private struct Spline<Entry> {
    var entries: [Entry?] = [nil, nil, nil, nil]
    private var distances = [-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]

    mutating func insert(_ entry: Entry, delta: Double) {
        if delta < 0 {
            if delta > distances[1] {
                distances[0] = distances[1]
                distances[1] = delta
                entries[0] = entries[1]
                entries[1] = entry
            } else if delta > distances[0] {
                distances[0] = delta
                entries[0] = entry
            }
        } else if delta < distances[2] {
            distances[3] = distances[2]
            distances[2] = delta
            entries[3] = entries[2]
            entries[2] = entry
        } else if delta < distances[3] {
            distances[3] = delta
            entries[3] = entry
        }
    }
}
