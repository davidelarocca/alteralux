import AlteraluxEngine
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo decoded to scene-linear pixels and handed to the engine.
public struct LoadedImage: Sendable {
    /// The file the image came from (used again at export time for metadata).
    public let url: URL
    /// Scene-linear Rec. 2020 pixels, owned by the engine.
    public let source: SourceImage
    /// The size of `source`, in pixels: the photo's own, or smaller when it was decoded for a
    /// preview.
    public let width: Int
    public let height: Int
    /// `true` when the file was a camera RAW decoded with Apple's RAW engine.
    public let isRaw: Bool
    /// `true` when the pixels already hold the exposure the engine's meter reads for the photo
    /// as it was shot (ADR 0022), with the highlights and shadows changed after it (ADR 0019):
    /// the film is then exposed with the meter off, whatever the adjustments say.
    public let isMetered: Bool
}

/// A white balance: what the decoder takes as neutral.
public struct WhiteBalance: Equatable, Sendable {
    /// The temperature of the light, in kelvin.
    public var temperature: Double
    /// The shift between green and magenta, in the decoder's units.
    public var tint: Double

    public init(temperature: Double, tint: Double) {
        self.temperature = temperature
        self.tint = tint
    }
}

/// Decodes image files to the scene-linear RGB the engine expects.
///
/// RAW files go through `CIRAWFilter`, the same decoder Photos uses, with
/// every tone and look adjustment turned off so the result is linear sensor
/// light. Other formats (TIFF, EXR, HEIC, JPEG, PNG) go through ImageIO and are
/// linearized by Core Image.
///
/// This decodes a file once. The app keeps a ``PhotoDecoder`` for the photo it shows, which
/// decodes it again at another size or with another white balance without starting over.
public enum ImageLoader {
    /// The color space of the pixels handed to the engine.
    public static let sceneColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

    /// Decodes `url`.
    ///
    /// - Parameter maxDimension: when set, the image is downscaled so its long
    ///   side is at most this many pixels (useful for thumbnails and tests).
    public static func load(_ url: URL, maxDimension: Int? = nil) throws -> LoadedImage {
        let isRaw = isRawFile(url)
        let image: CIImage = if isRaw {
            try rawImage(
                from: rawFilter(for: url), url: url, maxDimension: maxDimension, whiteBalance: nil,
            )
        } else {
            try scaled(standardImage(for: url), maxDimension: maxDimension)
        }
        return try pixels(of: image, url: url).loaded(from: url, isRaw: isRaw)
    }

    /// The photo as the system renders it by default, for thumbnails and the
    /// before/after comparison. RAW files get Apple's standard RAW rendering.
    ///
    /// - Parameter maxDimension: long side of the result, in pixels.
    public static func originalPreview(of url: URL, maxDimension: Int) -> CGImage? {
        guard let source = MendedDNG.imageSource(for: url) else { return nil }
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

    /// The RAW decoder for `url`, set for scene-linear output.
    static func rawFilter(for url: URL) throws -> CIRAWFilter {
        // A DNG with a fault the decoder refuses is handed over mended (see `MendedDNG`).
        let mended = MendedDNG.data(for: url).flatMap { CIRAWFilter(imageData: $0, identifierHint: MendedDNG.typeIdentifier) }
        guard let filter = mended ?? CIRAWFilter(imageURL: url) else {
            throw AlteraluxError.unreadableImage(url)
        }
        // Scene-linear output: no tone curve, no local tone mapping, no gamut
        // mapping to the output space, no sharpening. The film simulation
        // supplies all of those itself.
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.localToneMapAmount = 0
        filter.isGamutMappingEnabled = false
        filter.sharpnessAmount = 0
        return filter
    }

    /// The photo out of the RAW decoder, at the size and with the white balance asked.
    ///
    /// The decoder scales the photo itself, which is much quicker than decoding it whole and
    /// reducing it afterwards.
    ///
    /// - Parameters:
    ///   - maxDimension: the long side of the result, in pixels; `nil` for the photo's own size.
    ///   - whiteBalance: what to take as neutral; `nil` leaves what the filter is set to.
    ///   - lensCorrection: whether to correct the lens, where the decoder knows how; `nil`
    ///     leaves what the filter is set to.
    static func rawImage(
        from filter: CIRAWFilter, url: URL, maxDimension: Int?, whiteBalance: WhiteBalance?,
        lensCorrection: Bool? = nil,
    ) throws -> CIImage {
        if let whiteBalance {
            filter.neutralTemperature = Float(whiteBalance.temperature)
            filter.neutralTint = Float(whiteBalance.tint)
        }
        if let lensCorrection, filter.isLensCorrectionSupported {
            filter.isLensCorrectionEnabled = lensCorrection
        }
        let longSide = max(filter.nativeSize.width, filter.nativeSize.height)
        var scale = 1.0
        if let maxDimension, longSide > CGFloat(maxDimension) {
            scale = Double(maxDimension) / Double(longSide)
        }
        filter.scaleFactor = Float(scale)
        guard let image = filter.outputImage else {
            throw AlteraluxError.unreadableImage(url)
        }
        return image
    }

    /// A file that is not a RAW, as Core Image reads it.
    static func standardImage(for url: URL) throws -> CIImage {
        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true,
            // HDR photos (e.g. HEIC with a gain map) keep their highlights.
            .expandToHDR: true,
        ]
        guard let image = CIImage(contentsOf: url, options: options) else {
            throw AlteraluxError.unreadableImage(url)
        }
        return image
    }

    /// `image` reduced so its long side is at most `maxDimension` pixels.
    static func scaled(_ image: CIImage, maxDimension: Int?) -> CIImage {
        guard let maxDimension else { return image }
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > CGFloat(maxDimension) else { return image }
        let scale = CGFloat(maxDimension) / longSide
        return image.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0],
        )
    }

    /// A thumbnail turned and mirrored as `crop` says, neither straightened nor cut: how the
    /// library shows a photo turned there. The thumbnail itself when the frame does neither.
    public static func oriented(_ thumbnail: CGImage, by crop: PhotoCrop) -> CGImage? {
        guard crop.reorients else { return thumbnail }
        // A quarter turn clockwise is what Core Image calls the orientation "right".
        var image = CIImage(cgImage: thumbnail).oriented([.up, .right, .down, .left][crop.turns])
        if crop.isFlipped {
            image = image.oriented(.upMirrored)
        }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(image, from: image.extent)
    }

    /// `image` turned, mirrored, straightened and cut as `crop` says. `image` is the whole photo,
    /// upright, at any size: the frame is relative to it.
    static func framed(_ image: CIImage, by crop: PhotoCrop) -> CIImage {
        // A quarter turn clockwise is what Core Image calls the orientation "right".
        var image = image.oriented([.up, .right, .down, .left][crop.turns])
        if crop.isFlipped {
            image = image.oriented(.upMirrored)
        }
        image = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY),
        )
        let size = image.extent.size
        var turned = image
        if crop.angle != 0 {
            // Core Image's y points up: a clockwise turn on screen is a negative angle here.
            let turn = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                .rotated(by: -crop.angle * .pi / 180)
                .translatedBy(x: -size.width / 2, y: -size.height / 2)
            // Clamped first, so the edges of the frame are not blended with the empty corners.
            turned = image.clampedToExtent().transformed(by: turn)
        }
        let pixels = crop.pixelRect(in: size)
        // From the top left to Core Image's bottom left, on whole pixels.
        let rect = CGRect(
            x: pixels.minX.rounded(), y: (size.height - pixels.maxY).rounded(),
            width: max(1, pixels.width.rounded()), height: max(1, pixels.height.rounded()),
        )
        return turned.cropped(to: rect.intersection(CGRect(origin: .zero, size: size)))
    }

    /// Renders `image` to scene-linear pixels.
    static func pixels(of image: CIImage, url: URL) throws -> DecodedPixels {
        // Normalize the origin.
        let image = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY),
        )
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0, !extent.isInfinite else {
            throw AlteraluxError.unreadableImage(url)
        }

        // RGBA 32-bit float, top row first.
        let bytesPerRow = width * 16
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                image, toBitmap: base, rowBytes: bytesPerRow, bounds: extent,
                format: .RGBAf, colorSpace: sceneColorSpace,
            )
        }
        return DecodedPixels(pixels: pixels, width: width, height: height)
    }
}

/// Scene-linear RGBA pixels out of Core Image, 32-bit float, top row first.
struct DecodedPixels: Sendable {
    let pixels: Data
    let width: Int
    let height: Int
    /// Whether the meter's exposure is already in the pixels (see `LoadedImage.isMetered`).
    var isMetered = false

    /// Hands the pixels to the engine.
    func loaded(from url: URL, isRaw: Bool) throws -> LoadedImage {
        let source = try SourceImage.fromF32Pixels(
            width: UInt32(width), height: UInt32(height), channels: 4, pixels: pixels,
        )
        return LoadedImage(url: url, source: source, width: width, height: height, isRaw: isRaw, isMetered: isMetered)
    }
}
