import CoreImage
import Foundation

/// The white balance that makes one point of a photo gray: what the dropper of the white balance
/// gives, where the user clicks something that should have no color (a gray card, a white wall,
/// a cloud).
///
/// The photo is decoded framed as the adjustments frame it, so the point is where the user saw
/// it, and the color of a small patch around it is measured. The decoder's neutral is moved by
/// that color and the patch measured again, until it is gray.
enum NeutralPoint {
    /// The long side the photo is decoded at to be measured, in pixels.
    static let measuredSide = 1024
    /// How far the patch measured reaches around the point, in pixels at `measuredSide`: a
    /// patch of 7 × 7, which averages the noise of a single pixel away.
    static let patchRadius = 3
    /// How many times the photo is measured again at most.
    static let rounds = 4
    /// How close to gray the patch must be, as xy, to stop measuring.
    static let tolerance = 0.0005
    /// The share of the patch's pixels that must be neither clipped nor too dark.
    static let minimumUsable = 0.5

    /// The point does not have a color that can be made gray.
    enum Problem: Error, Equatable {
        /// Clipped, or nearly black: its color is not the light's.
        case unmeasurable
    }

    /// The red, green and blue of the patch of `image` around `point`, averaged over the pixels
    /// neither clipped nor too dark. `point` is in the picture's own terms, from its top left
    /// corner, 0 to 1 across and down. `nil` when too few pixels can be measured.
    static func color(of image: CIImage, at point: CGPoint) -> SIMD3<Double>? {
        let extent = image.extent.integral
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return nil }
        // Core Image's y points up.
        let center = CGPoint(
            x: extent.minX + min(max(point.x, 0), 1) * extent.width,
            y: extent.maxY - min(max(point.y, 0), 1) * extent.height,
        )
        let side = CGFloat(2 * patchRadius + 1)
        let patch = CGRect(
            x: (center.x - side / 2).rounded(.down), y: (center.y - side / 2).rounded(.down), width: side, height: side,
        )
        .intersection(extent)
        guard !patch.isNull, patch.width >= 1, patch.height >= 1 else { return nil }
        let width = Int(patch.width)
        let height = Int(patch.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        AutomaticWhiteBalance.context.render(
            image, toBitmap: &pixels, rowBytes: width * 16, bounds: patch, format: .RGBAf,
            colorSpace: AutomaticWhiteBalance.space,
        )
        return mean(pixels, count: width * height)
    }

    /// The mean of each channel over the pixels that are neither clipped nor too dark, as red,
    /// green and blue. `nil` when fewer than half are left.
    static func mean(_ pixels: [Float], count: Int) -> SIMD3<Double>? {
        var sums = SIMD3<Double>()
        var used = 0
        for index in stride(from: 0, to: count * 4, by: 4) {
            let color = SIMD3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2]))
            guard color.max() < 0.95, color.sum() / 3 > 0.005, color.min() > 0 else { continue }
            sums += color
            used += 1
        }
        guard used > 0, Double(used) >= minimumUsable * Double(count) else { return nil }
        return sums / Double(used)
    }

    /// How far the color `rgb` is from gray, as xy: what the decoder's neutral moves by.
    static func cast(of rgb: SIMD3<Double>) -> CGPoint {
        let chromaticity = AutomaticWhiteBalance.chromaticity(rgb)
        let white = AutomaticWhiteBalance.whitePoint
        return CGPoint(x: chromaticity.x - white.x, y: chromaticity.y - white.y)
    }
}
