import CoreImage
import Foundation

/// A white balance found in the pixels of a RAW, for photos that adapt to their light.
///
/// The photo is decoded small with the camera's white balance and the color the scene averages
/// to is measured, leaving out clipped and very dark pixels (a "shades of gray" mean, which a
/// large colored area pulls less than a plain average). The decoder's neutral is moved by that
/// color and the photo measured again, twice. The camera's own white balance is usually close:
/// it is kept unless the one found is far from it, and then the photo is moved only part of the
/// way, since a measurement can be fooled by a scene that is colored on its own.
enum AutomaticWhiteBalance {
    /// The long side the photo is measured at, in pixels.
    static let measuredSide = 256
    /// How far, in mired, the white balance found must be from the camera's to be used.
    static let miredThreshold = 25.0
    /// How far the tint found must be from the camera's to be used.
    static let tintThreshold = 15.0
    /// How much of the way from the camera's white balance to the one found the photo is moved.
    static let share = 0.6
    /// The share of the pixels that must be neither clipped nor too dark to measure the photo.
    static let minimumUsable = 0.2
    /// The temperatures and tints the result stays within, as the inspector's sliders do.
    static let temperatures = 2000.0 ... 12000.0
    static let tints = -150.0 ... 150.0

    private static let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let context = CIContext(options: [
        .workingColorSpace: space,
        .workingFormat: NSNumber(value: CIFormat.RGBAf.rawValue),
        .cacheIntermediates: false,
    ])
    /// The white point of linear sRGB, D65, as xy.
    private static let whitePoint = CGPoint(x: 0.3127, y: 0.3290)

    /// The white balance to start the photo from: the camera's, unless the one measured is far
    /// from it. `nil` when the photo cannot be measured.
    ///
    /// The filter is left with the camera's white balance.
    static func whiteBalance(of filter: CIRAWFilter, asShot: WhiteBalance) -> WhiteBalance? {
        guard let found = measure(filter, asShot: asShot) else { return nil }
        return adopted(found, asShot: asShot)
    }

    /// The white balance a photo measured `found` starts from: the camera's when the two are
    /// close, otherwise part of the way toward `found`.
    static func adopted(_ found: WhiteBalance, asShot: WhiteBalance) -> WhiteBalance {
        let asShotMired = mired(asShot.temperature)
        let miredShift = mired(found.temperature) - asShotMired
        let tintShift = found.tint - asShot.tint
        guard abs(miredShift) > miredThreshold || abs(tintShift) > tintThreshold else { return asShot }
        let temperature = 1_000_000 / (asShotMired + share * miredShift)
        return WhiteBalance(
            temperature: min(max(temperature, temperatures.lowerBound), temperatures.upperBound),
            tint: min(max(asShot.tint + share * tintShift, tints.lowerBound), tints.upperBound),
        )
    }

    /// The white balance under which the photo averages to gray. `nil` when too few pixels can
    /// be measured.
    static func measure(_ filter: CIRAWFilter, asShot: WhiteBalance) -> WhiteBalance? {
        let scale = filter.scaleFactor
        defer {
            filter.neutralTemperature = Float(asShot.temperature)
            filter.neutralTint = Float(asShot.tint)
            filter.scaleFactor = scale
        }
        filter.neutralTemperature = Float(asShot.temperature)
        filter.neutralTint = Float(asShot.tint)
        let longSide = max(filter.nativeSize.width, filter.nativeSize.height)
        guard longSide > 0 else { return nil }
        filter.scaleFactor = Float(min(1, Double(measuredSide) / Double(longSide)))

        var neutral = filter.neutralChromaticity
        for _ in 0 ..< 2 {
            guard let cast = cast(of: filter) else { return nil }
            neutral.x += cast.x - whitePoint.x
            neutral.y += cast.y - whitePoint.y
            filter.neutralChromaticity = neutral
        }
        return WhiteBalance(temperature: Double(filter.neutralTemperature), tint: Double(filter.neutralTint))
    }

    /// The color, as xy, the photo decoded by `filter` averages to.
    private static func cast(of filter: CIRAWFilter) -> CGPoint? {
        guard let image = filter.outputImage else { return nil }
        let extent = image.extent.integral
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return nil }
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image, toBitmap: &pixels, rowBytes: width * 16, bounds: extent, format: .RGBAf, colorSpace: space,
        )
        guard let mean = shadesOfGray(pixels, count: width * height) else { return nil }
        return chromaticity(mean / mean.y)
    }

    /// The Minkowski mean (power 6) of each channel over the pixels that are neither clipped nor
    /// too dark, as red, green and blue. `nil` when too few are left.
    static func shadesOfGray(_ pixels: [Float], count: Int) -> SIMD3<Double>? {
        var sums = SIMD3<Double>()
        var used = 0
        for index in stride(from: 0, to: count * 4, by: 4) {
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            guard max(red, green, blue) < 0.95, (red + green + blue) / 3 > 0.02, min(red, green, blue) > 0 else {
                continue
            }
            sums += SIMD3(pow(red, 6), pow(green, 6), pow(blue, 6))
            used += 1
        }
        guard used > 0, Double(used) >= minimumUsable * Double(count) else { return nil }
        let means = sums / Double(used)
        return SIMD3(pow(means.x, 1 / 6), pow(means.y, 1 / 6), pow(means.z, 1 / 6))
    }

    /// The xy chromaticity of a linear sRGB color (red, green, blue).
    private static func chromaticity(_ rgb: SIMD3<Double>) -> CGPoint {
        let tristimulus = SIMD3(
            (SIMD3(0.4124, 0.3576, 0.1805) * rgb).sum(),
            (SIMD3(0.2126, 0.7152, 0.0722) * rgb).sum(),
            (SIMD3(0.0193, 0.1192, 0.9505) * rgb).sum(),
        )
        let sum = tristimulus.sum()
        return CGPoint(x: tristimulus.x / sum, y: tristimulus.y / sum)
    }

    private static func mired(_ temperature: Double) -> Double {
        1_000_000 / temperature
    }
}
