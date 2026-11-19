import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import SpektrafilmEngine
import UniformTypeIdentifiers

/// A photo decoded to scene-linear pixels and handed to the engine.
public struct LoadedImage: Sendable {
    /// The file the image came from (used again at export time for metadata).
    public let url: URL
    /// Scene-linear Rec. 2020 pixels, owned by the engine.
    public let source: SourceImage
    public let width: Int
    public let height: Int
    /// `true` when the file was a camera RAW decoded with Apple's RAW engine.
    public let isRaw: Bool
}

/// Decodes image files to the scene-linear RGB the engine expects.
///
/// RAW files go through `CIRAWFilter`, the same decoder Photos uses, with
/// every tone and look adjustment turned off so the result is linear sensor
/// light. Other formats (TIFF, EXR, HEIC, JPEG, PNG) go through ImageIO and are
/// linearized by Core Image.
public enum ImageLoader {
    /// The color space of the pixels handed to the engine.
    public static let sceneColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

    /// Decodes `url`.
    ///
    /// - Parameter maxDimension: when set, the image is downscaled so its long
    ///   side is at most this many pixels (useful for thumbnails and tests).
    public static func load(_ url: URL, maxDimension: Int? = nil) throws -> LoadedImage {
        let isRaw = isRawFile(url)
        var image = try isRaw ? decodeRaw(url) : decodeStandard(url)

        // Normalize the origin, then optionally downscale.
        image = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if let maxDimension {
            let longSide = max(image.extent.width, image.extent.height)
            if longSide > CGFloat(maxDimension) {
                let scale = CGFloat(maxDimension) / longSide
                image = image.applyingFilter(
                    "CILanczosScaleTransform",
                    parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
            }
        }

        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0, !extent.isInfinite else {
            throw SpektrafilmError.unreadableImage(url)
        }

        // RGBA 32-bit float, top row first.
        let bytesPerRow = width * 16
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                image, toBitmap: base, rowBytes: bytesPerRow, bounds: extent,
                format: .RGBAf, colorSpace: sceneColorSpace)
        }

        let source = try SourceImage.fromF32Pixels(
            width: UInt32(width), height: UInt32(height), channels: 4, pixels: pixels)
        return LoadedImage(url: url, source: source, width: width, height: height, isRaw: isRaw)
    }

    /// The photo as the system renders it by default, for thumbnails and the
    /// before/after comparison. RAW files get Apple's standard RAW rendering.
    ///
    /// - Parameter maxDimension: long side of the result, in pixels.
    public static func originalPreview(of url: URL, maxDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Whether `url` looks like a camera RAW file (by its file type).
    public static func isRawFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .rawImage)
    }

    // MARK: - Decoding

    private static let context = CIContext(options: [
        .workingColorSpace: sceneColorSpace,
        .workingFormat: NSNumber(value: CIFormat.RGBAf.rawValue),
        .cacheIntermediates: false,
    ])

    private static func decodeRaw(_ url: URL) throws -> CIImage {
        guard let filter = CIRAWFilter(imageURL: url) else {
            throw SpektrafilmError.unreadableImage(url)
        }
        // Scene-linear output: no tone curve, no local tone mapping, no gamut
        // mapping to the output space, no sharpening. The film simulation
        // supplies all of those itself.
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.localToneMapAmount = 0
        filter.isGamutMappingEnabled = false
        filter.sharpnessAmount = 0
        guard let image = filter.outputImage else {
            throw SpektrafilmError.unreadableImage(url)
        }
        return image
    }

    private static func decodeStandard(_ url: URL) throws -> CIImage {
        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true,
            // HDR photos (e.g. HEIC with a gain map) keep their highlights.
            .expandToHDR: true,
        ]
        guard let image = CIImage(contentsOf: url, options: options) else {
            throw SpektrafilmError.unreadableImage(url)
        }
        return image
    }
}
