import Foundation

/// Who corrects one part of a photo's lens: Apple's RAW decoder, what the camera recorded in the
/// file, or lensfun's profile of the lens.
public enum LensCorrectionSource: Sendable, Equatable {
    case apple, camera, lensfun
}

/// The lens correction of a photo when the camera recorded some of it (ADR 0015): as radial
/// curves, whatever the camera's own reading, with the parts the camera did not record taken from
/// lensfun, and only the vignetting when Apple's decoder corrects the geometry itself.
///
/// Coordinates are in the pixels of the photo as decoded, as in `LensCorrection`: the origin at the
/// top left, `y` down, the first pixel's center at (0, 0). Radii are in half diagonals.
public struct CameraLensCorrection: Sendable, Equatable {
    /// The lens, as the photo names it, for the inspector.
    public let lensName: String
    /// Who corrects the distortion and the fringes, and who the vignetting; `nil` for nobody.
    public let geometrySource: LensCorrectionSource?
    public let vignettingSource: LensCorrectionSource?
    /// For each channel, the factor by which the radius of a point of the corrected picture is
    /// multiplied to find where it comes from in the photo as shot: 1 everywhere when this
    /// correction does not move the pixels.
    public let red: RadialCurve
    public let green: RadialCurve
    public let blue: RadialCurve
    /// The fraction of the light the lens let through, by the radius the pixel is taken from. The
    /// pixel is divided by it.
    public let light: RadialCurve
    /// The center of the picture, in pixels.
    public let center: SIMD2<Double>
    /// The half diagonal of the picture in pixels: the radius 1 of the curves.
    public let unit: Double
    /// The zoom that makes the corrected picture fill the frame with no empty edges: a point of
    /// the corrected picture is looked up at its distance from `center` divided by `scale`.
    public let scale: Double

    /// The correction of a photo of `width` × `height` pixels.
    ///
    /// - Parameters:
    ///   - geometry: the curves that move the pixels; `nil` when nothing here moves them (no one
    ///     corrects the geometry, or Apple's decoder already did).
    ///   - light: the light kept, by the radius in the photo as shot; `nil` for no vignetting.
    ///   - shotRadius: when the pixels are not moved here but were by Apple's decoder, the curve
    ///     the camera recorded for green, which tells where each pixel was in the photo as shot,
    ///     so that its vignetting is read there.
    public init?(
        lensName: String,
        geometry: CameraLensData.Geometry?, geometrySource: LensCorrectionSource?,
        light: RadialCurve?, vignettingSource: LensCorrectionSource?,
        shotRadius: RadialCurve? = nil,
        width: Int, height: Int,
    ) {
        guard width > 0, height > 0, geometry != nil || light != nil else { return nil }
        self.lensName = lensName
        self.geometrySource = geometrySource
        self.vignettingSource = light == nil ? nil : vignettingSource
        let identity = RadialCurve.constant(1)
        red = geometry?.red ?? identity
        green = geometry?.green ?? identity
        blue = geometry?.blue ?? identity
        center = SIMD2(Double(width - 1) / 2, Double(height - 1) / 2)
        unit = Double(width * width + height * height).squareRoot() / 2
        let fill = Self.autoScale(curves: [red, green, blue], width: Double(width), height: Double(height))
        scale = geometry == nil ? 1 : fill
        if let light, geometry == nil, let shotRadius {
            // Where Apple's decoder moved the pixels as the camera's curve says, with the same zoom.
            let zoom = Self.autoScale(curves: [shotRadius], width: Double(width), height: Double(height))
            self.light = RadialCurve(sampling: { radius in
                light.value(at: radius / zoom * shotRadius.value(at: radius / zoom))
            })
        } else {
            self.light = light ?? identity
        }
    }

    /// Whether this correction moves the pixels: not when it only lifts the vignetting.
    public var movesPixels: Bool {
        scale != 1 || ![red, green, blue].allSatisfy { $0.isEverywhere(1) }
    }

    /// Where in the photo as shot the pixel at `point` of the corrected picture gets its
    /// `channel` from: 0 red, 1 green, 2 blue. The scale is included. This is the reference the
    /// kernel must match.
    public func sourcePoint(ofCorrected point: SIMD2<Double>, channel: Int) -> SIMD2<Double> {
        let offset = (point - center) / scale
        let radius = (offset.x * offset.x + offset.y * offset.y).squareRoot() / unit
        let curve = channel == 0 ? red : channel == 2 ? blue : green
        return center + offset * curve.value(at: radius)
    }

    /// The farthest, in pixels of the whole photo, that a pixel of the corrected picture is taken
    /// from its own place, for any channel, up to the corners.
    public func largestShift() -> Double {
        var largest = 0.0
        for step in 0 ... 400 {
            let radius = 1.05 * Double(step) / 400
            for curve in [red, green, blue] {
                let shift = radius * abs(curve.value(at: radius / scale) / scale - 1)
                largest = max(largest, shift)
            }
        }
        return largest * unit
    }

    /// The factor to multiply the pixel taken from `point` by to remove its vignetting.
    public func vignettingGain(at point: SIMD2<Double>) -> Double {
        let offset = point - center
        let radius = (offset.x * offset.x + offset.y * offset.y).squareRoot() / unit
        return 1 / max(light.value(at: radius), 1e-4)
    }

    /// The smallest zoom with which every point on the edge of the corrected picture comes from
    /// inside the photo as shot, for every channel, with a margin of one permille.
    ///
    /// The curves move points along their radius only, so a point of the edge at the distance `R`
    /// from the center stays inside when the curve, read at `R / scale`, is at most `scale`. Every
    /// `R` from half the short side to the half diagonal is on the edge; the zoom is the fixed
    /// point of taking the largest of those values, found in a few rounds.
    static func autoScale(curves: [RadialCurve], width: Double, height: Double) -> Double {
        let halfDiagonal = (width * width + height * height).squareRoot() / 2
        let shortest = min(width, height) / 2 / halfDiagonal
        let samples = 400
        var scale = 1.0
        for _ in 0 ..< 20 {
            var largest = 0.0
            for step in 0 ... samples {
                let radius = shortest + (1 - shortest) * Double(step) / Double(samples)
                for curve in curves {
                    largest = max(largest, curve.value(at: radius / scale))
                }
            }
            if abs(largest - scale) < 1e-9 {
                break
            }
            scale = largest
        }
        return scale * 1.001
    }
}

public extension CameraLensCorrection {
    /// The correction of a photo of `size` pixels (width, height) from what its camera recorded and
    /// lensfun's profile, as ADR 0015 orders them: the geometry by Apple's decoder where it knows
    /// the lens, then by the camera, then by lensfun; the vignetting by the camera, except where
    /// Apple's decoder lifts it itself, then by lensfun when Apple's decoder leaves the photo
    /// alone. `nil` when the camera recorded nothing that applies: lensfun's profile alone, or
    /// Apple's decoder alone, does it then.
    static func combining(
        camera: CameraLensData?, lensfun: LensCorrection?, appleCorrects: Bool, lensName: String, size: SIMD2<Int>,
    ) -> CameraLensCorrection? {
        guard let camera else { return nil }
        let (width, height) = (size.x, size.y)
        if appleCorrects {
            guard let vignetting = camera.vignetting, !camera.maker.appleLiftsVignetting else { return nil }
            return CameraLensCorrection(
                lensName: lensName, geometry: nil, geometrySource: .apple, light: vignetting,
                vignettingSource: .camera, shotRadius: camera.geometry?.green, width: width, height: height,
            )
        }
        let lensfunGeometry = lensfun?.radialGeometry(width: width, height: height)
        let lensfunLight = lensfun?.radialLight(width: width, height: height)
        let geometry = camera.geometry ?? lensfunGeometry
        let light = camera.vignetting ?? lensfunLight
        return CameraLensCorrection(
            lensName: lensName,
            geometry: geometry, geometrySource: camera.geometry != nil ? .camera : lensfunGeometry != nil ? .lensfun : nil,
            light: light, vignettingSource: camera.vignetting != nil ? .camera : lensfunLight != nil ? .lensfun : nil,
            width: width, height: height,
        )
    }
}

extension LensCorrection {
    /// The distortion and the fringes of this profile as radial curves over the half diagonal of
    /// a photo of `width` × `height` pixels, without its zoom; `nil` when it corrects neither.
    func radialGeometry(width: Int, height: Int) -> CameraLensData.Geometry? {
        guard correctsDistortion || correctsFringing else { return nil }
        let halfDiagonal = Double(width * width + height * height).squareRoot() / 2
        let direction = SIMD2(Double(width), Double(height)) / (2 * halfDiagonal)
        func curve(_ channel: Int) -> RadialCurve {
            RadialCurve(sampling: { radius in
                let along = max(radius, 1e-4) * halfDiagonal
                let source = sourcePoint(ofCorrected: center + direction * along * scale, channel: channel) - center
                return (source.x * source.x + source.y * source.y).squareRoot() / along
            })
        }
        return CameraLensData.Geometry(red: curve(0), green: curve(1), blue: curve(2))
    }

    /// The vignetting of this profile as the light kept by the radius in half diagonals; `nil`
    /// when it has none.
    func radialLight(width: Int, height: Int) -> RadialCurve? {
        guard correctsVignetting else { return nil }
        let halfDiagonal = Double(width * width + height * height).squareRoot() / 2
        let direction = SIMD2(Double(width), Double(height)) / (2 * halfDiagonal)
        return RadialCurve(sampling: { radius in
            1 / vignettingGain(at: center + direction * radius * halfDiagonal)
        })
    }
}
