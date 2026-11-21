import Foundation

/// The corrections the camera recorded in a RAW for the lens on it, at the moment of the shot:
/// distortion, lateral color fringing and vignetting, as curves over the distance from the center
/// of the picture (ADR 0015).
///
/// Each curve has one value per knot. Knot `i` of `n` lies at the radius `(i + 0.5) / (n - 1)`
/// of the half diagonal; between knots the value goes in a straight line, and before the first or
/// past the last it stays the first or the last value, as darktable reads the same data.
///
/// Coordinates are in the pixels of the photo as decoded, as in `LensCorrection`: the origin at the
/// top left, `y` down, the first pixel's center at (0, 0).
public struct CameraLensCorrection: Sendable, Equatable {
    /// The lens, as the photo names it, for the inspector.
    public let lensName: String
    /// For green, the factor by which the radius of a point of the corrected picture is multiplied
    /// to find where it comes from in the photo as shot.
    public let green: [Double]
    /// The same for red and for blue: green's factor times their own, which moves them apart from
    /// green to take away the colored fringes.
    public let red: [Double]
    public let blue: [Double]
    /// The fraction of the light the lens lets through at each knot, measured on the photo as
    /// shot: 1 at the center, less towards the corners. The pixel is divided by it.
    public let vignetting: [Double]
    /// The center of the picture, in pixels.
    public let center: SIMD2<Double>
    /// The half diagonal of the picture in pixels: the radius 1 of the knots.
    public let unit: Double
    /// The zoom that makes the corrected picture fill the frame with no empty edges: a point of
    /// the corrected picture is looked up at its distance from `center` divided by `scale`.
    public let scale: Double

    /// The correction for a photo of `width` × `height` pixels, with the curves as the camera
    /// gives them; `nil` when they are not of one length between 2 and 16 knots.
    public init?(
        lensName: String, green: [Double], red: [Double], blue: [Double], vignetting: [Double],
        width: Int, height: Int,
    ) {
        let count = green.count
        guard (2 ... 16).contains(count), red.count == count, blue.count == count, vignetting.count == count,
              width > 0, height > 0, vignetting.allSatisfy({ $0 > 0 })
        else { return nil }
        self.lensName = lensName
        self.green = green
        self.red = red
        self.blue = blue
        self.vignetting = vignetting
        center = SIMD2(Double(width - 1) / 2, Double(height - 1) / 2)
        unit = Double(width * width + height * height).squareRoot() / 2
        scale = Self.autoScale(curves: [red, green, blue], width: Double(width), height: Double(height))
    }

    /// The number of knots of every curve.
    public var knotCount: Int {
        green.count
    }

    /// Where in the photo as shot the pixel at `point` of the corrected picture gets its
    /// `channel` from: 0 red, 1 green, 2 blue. The scale is included. This is the reference the
    /// kernel must match.
    public func sourcePoint(ofCorrected point: SIMD2<Double>, channel: Int) -> SIMD2<Double> {
        let offset = (point - center) / scale
        let radius = (offset.x * offset.x + offset.y * offset.y).squareRoot() / unit
        let curve = channel == 0 ? red : channel == 2 ? blue : green
        return center + offset * Self.value(of: curve, at: radius)
    }

    /// The factor to multiply the pixel at `point` of the photo as shot by to remove its
    /// vignetting.
    public func vignettingGain(at point: SIMD2<Double>) -> Double {
        let offset = point - center
        let radius = (offset.x * offset.x + offset.y * offset.y).squareRoot() / unit
        return 1 / Self.value(of: vignetting, at: radius)
    }

    /// The value of `curve` at `radius`, in half diagonals.
    static func value(of curve: [Double], at radius: Double) -> Double {
        let position = radius * Double(curve.count - 1) - 0.5
        guard position > 0 else { return curve[0] }
        guard position < Double(curve.count - 1) else { return curve[curve.count - 1] }
        let index = Int(position)
        let fraction = position - Double(index)
        return curve[index] + (curve[index + 1] - curve[index]) * fraction
    }

    /// The smallest zoom with which every point on the edge of the corrected picture comes from
    /// inside the photo as shot, for every channel, with a margin of one permille.
    ///
    /// The curves move points along their radius only, so a point of the edge at the distance `R`
    /// from the center stays inside when the curve, read at `R / scale`, is at most `scale`. Every
    /// `R` from half the short side to the half diagonal is on the edge; the zoom is the fixed
    /// point of taking the largest of those values, found in a few rounds.
    static func autoScale(curves: [[Double]], width: Double, height: Double) -> Double {
        let halfDiagonal = (width * width + height * height).squareRoot() / 2
        let shortest = min(width, height) / 2 / halfDiagonal
        let samples = 400
        var scale = 1.0
        for _ in 0 ..< 20 {
            var largest = 0.0
            for step in 0 ... samples {
                let radius = shortest + (1 - shortest) * Double(step) / Double(samples)
                for curve in curves {
                    largest = max(largest, value(of: curve, at: radius / scale))
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
