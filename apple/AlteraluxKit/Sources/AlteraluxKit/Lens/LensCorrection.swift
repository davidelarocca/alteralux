import Foundation

/// The corrections a lens profile asks for one photo: distortion, lateral color fringing and
/// vignetting, interpolated at the photo's focal length, aperture and focus distance, and
/// expressed in the pixels of the photo so a kernel can use them as they are.
///
/// Coordinates are in the pixels of the photo as decoded: the origin is the top left, `x` runs
/// right and `y` runs down, and the center of the first pixel is (0, 0), so the last pixel's
/// center is (width - 1, height - 1), as in lensfun. A kernel that samples at pixel corners adds
/// half a pixel when it goes in and takes it off when it comes out.
///
/// Every radius is measured in `unit` pixels from `center` (lensfun's "normalized" coordinates,
/// where one unit is the real focal length of the picture), and the terms are already rescaled
/// from the sensor the lens was calibrated on to this photo's, so a kernel only applies the
/// formulas below. The numbers match lensfun's `lfModifier` (`modifier.cpp`, `mod-coord.cpp`,
/// `mod-subpix.cpp`, `mod-color.cpp`).
public struct LensCorrection: Sendable, Equatable {
    /// The lens, maker and model, for the inspector.
    public let lensName: String

    /// The distortion model. `Rd = Ru * f(Ru)` where `Ru` is the radius of a point of the
    /// corrected picture and `Rd` the radius it comes from in the shot picture, both in
    /// `distortionUnit` pixels:
    /// - `poly3`: `f = 1 + k1 r^2`, with `distortionTerms = (k1, 0, 0)`
    /// - `poly5`: `f = 1 + k1 r^2 + k2 r^4`, with `(k1, k2, 0)`
    /// - `ptlens`: `f = a r^3 + b r^2 + c r + 1`, with `(a, b, c)`
    public let distortionModel: LensDistortionModel
    public let distortionTerms: SIMD3<Double>
    /// Pixels in one unit of the radius used by the distortion, the fringing and the vignetting.
    public let distortionUnit: Double
    /// The optical center of the picture, in pixels.
    public let center: SIMD2<Double>

    /// The fringing model. The red and the blue channel are sampled at `Rd = Ru * g(Ru)` with
    /// `g = v + c r + b r^2`, `Ru` being the radius after the distortion: the terms are
    /// `(v, c, b)`. A linear model is `(k, 0, 0)`. Green stays where it is.
    public let tcaModel: LensTCAModel
    public let tcaRed: SIMD3<Double>
    public let tcaBlue: SIMD3<Double>

    /// The vignetting gain is `1 / (1 + k1 r^2 + k2 r^4 + k3 r^6)` with `r` the distance from
    /// `center` in `vignettingUnit` pixels, for a point of the photo as shot. All zero when the
    /// profile has no vignetting for the photo.
    public let vignettingTerms: SIMD3<Double>
    public let vignettingUnit: Double

    /// The zoom that makes the corrected picture fill the frame with no empty edges: a point of
    /// the corrected picture is looked up at its distance from `center` divided by `scale`.
    public let scale: Double

    /// Whether the profile corrects the distortion of this photo.
    public var correctsDistortion: Bool {
        distortionModel != .none
    }

    /// Whether the profile corrects the lateral color fringing of this photo.
    public var correctsFringing: Bool {
        tcaModel != .none
    }

    /// Whether the profile corrects the vignetting of this photo.
    public var correctsVignetting: Bool {
        vignettingTerms != .zero
    }

    /// Where in the photo as shot the pixel at `point` of the corrected picture gets its
    /// `channel` from: 0 red, 1 green, 2 blue. The scale is included. This is the reference a
    /// kernel must match: the corrected picture is sampled at this point for each of its pixels.
    public func sourcePoint(ofCorrected point: SIMD2<Double>, channel: Int) -> SIMD2<Double> {
        let distorted = distortedUnitPoint(ofCorrected: point)
        var unitPoint = distorted
        if channel == 0 || channel == 2 {
            let terms = channel == 0 ? tcaRed : tcaBlue
            let radius = (distorted.x * distorted.x + distorted.y * distorted.y).squareRoot()
            let factor = terms.x + terms.y * radius + terms.z * radius * radius
            unitPoint = distorted * factor
        }
        return unitPoint * distortionUnit + center
    }

    /// The factor to multiply the pixel at `point` of the photo as shot by to remove its
    /// vignetting. 1 when there is none.
    public func vignettingGain(at point: SIMD2<Double>) -> Double {
        let offset = (point - center) / vignettingUnit
        let square = offset.x * offset.x + offset.y * offset.y
        let fourth = square * square
        let denominator = 1 + vignettingTerms.x * square + vignettingTerms.y * fourth + vignettingTerms.z * fourth * square
        return 1 / denominator
    }

    /// The point of the corrected picture in lens units, scaled and then distorted.
    private func distortedUnitPoint(ofCorrected point: SIMD2<Double>) -> SIMD2<Double> {
        let unitPoint = (point - center) / (distortionUnit * scale)
        return Self.distort(unitPoint, model: distortionModel, terms: distortionTerms)
    }

    /// The radius a point of the corrected picture comes from in the shot one, applied to the
    /// point: lensfun's `ModifyCoord_Dist_*`.
    static func distort(_ point: SIMD2<Double>, model: LensDistortionModel, terms: SIMD3<Double>) -> SIMD2<Double> {
        let square = point.x * point.x + point.y * point.y
        switch model {
        case .none:
            return point
        case .poly3:
            return point * (1 + terms.x * square)
        case .poly5:
            return point * (1 + terms.x * square + terms.y * square * square)
        case .ptlens:
            let radius = square.squareRoot()
            return point * (terms.x * square * radius + terms.y * square + terms.z * radius + 1)
        }
    }

    /// The scale that makes the corrected picture fill the frame: lensfun's `GetAutoScale`. In
    /// eight directions (the four corners and the four edge middles) it finds with Newton's
    /// method the radius of the corrected picture that the distortion sends to the edge of the
    /// shot one, and takes the largest ratio of the frame's radius to it, with a margin of one
    /// permille, and another when there is fringing correction, which moves the channels apart.
    static func autoScale(
        model: LensDistortionModel,
        terms: SIMD3<Double>,
        span: SIMD2<Double>,
        unitsPerPixel: Double,
        hasFringing: Bool,
    ) -> Double {
        let fringingMargin = hasFringing ? 1.001 : 1.0
        guard model != .none else { return fringingMargin }

        let halfX = span.x / 2 * unitsPerPixel
        let halfY = span.y / 2 * unitsPerPixel
        let cornerAngle = atan2(span.y, span.x)
        let cornerRadius = (span.x * span.x + span.y * span.y).squareRoot() * 0.5 * unitsPerPixel
        let directions: [(angle: Double, radius: Double)] = [
            (0, halfX), (cornerAngle, cornerRadius), (.pi / 2, halfY), (.pi - cornerAngle, cornerRadius),
            (.pi, halfX), (.pi + cornerAngle, cornerRadius), (.pi * 1.5, halfY), (2 * .pi - cornerAngle, cornerRadius),
        ]

        func excess(_ point: SIMD2<Double>) -> Double {
            max(abs(point.x) - halfX, abs(point.y) - halfY)
        }

        var scale = 0.01
        for direction in directions {
            let sine = sin(direction.angle)
            let cosine = cos(direction.angle)
            func residual(at radius: Double) -> Double {
                excess(distort(SIMD2(cosine * radius, sine * radius), model: model, terms: terms))
            }
            var radius = direction.radius
            var converged = false
            for _ in 0 ..< 50 {
                let value = residual(at: radius)
                if abs(value) < 1e-9 {
                    converged = true
                    break
                }
                let step = 1e-6
                let slope = (residual(at: radius + step) - value) / step
                guard slope != 0 else { break }
                radius -= value / slope
            }
            // Some fisheyes send the corners to infinity: such a direction says nothing.
            if converged, radius > 0 {
                scale = max(scale, direction.radius / radius)
            }
        }
        return scale * 1.001 * fringingMargin
    }
}
