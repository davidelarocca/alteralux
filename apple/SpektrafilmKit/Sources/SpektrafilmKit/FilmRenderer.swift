import CoreGraphics
import Foundation
import SpektrafilmEngine

/// A developed photo, ready to display or export.
public struct DevelopedImage: @unchecked Sendable { // concurrency: CGImage is immutable, the rest are values
    /// Display-linear image tagged with its color space. AppKit, SwiftUI and
    /// ImageIO color-manage it for the screen or the exported file.
    public let cgImage: CGImage
    public let width: Int
    public let height: Int
    public let stats: RenderStats
}

/// Output quality of a render.
public enum RenderQuality: Sendable, Equatable {
    /// Half-float pixels, limited to `maxDimension` on the long side (`0` =
    /// full resolution). For the live preview while adjusting.
    case preview(maxDimension: Int)
    /// Full resolution, 32-bit float pixels. For export.
    case full
}

/// Runs the film simulation off the main thread.
///
/// One renderer owns one engine, which keeps its calibrated pipeline between
/// renders: adjusting exposure, grain or filters re-renders in a fraction of
/// the time of the first render.
public final class FilmRenderer: Sendable {
    private let engine: Engine
    // The engine blocks while rendering; keep it off Swift's cooperative pool.
    private let queue = DispatchQueue(label: "spektrafilm.render", qos: .userInitiated)

    /// - Parameter dataDirectory: the engine's `data` folder (film and paper
    ///   profiles, spectral tables). The app ships it in its resources.
    public init(dataDirectory: URL, backend: BackendPreference = .automatic) throws {
        engine = try Engine(dataDir: dataDirectory.path, backend: backend)
    }

    /// The compute backend in use, for diagnostics (e.g. "wgpu" or "cpu").
    public var backendName: String { engine.backendName() }

    /// All film and paper stocks, films first.
    public func stocks() throws -> [StockInfo] {
        try engine.stocks()
    }

    /// Develops `image` with `settings`.
    public func render(
        _ image: LoadedImage, settings: DevelopSettings, quality: RenderQuality
    ) async throws -> DevelopedImage {
        try await render(image.source, settings: settings, quality: quality)
    }

    /// Develops an engine source image with `settings`.
    public func render(
        _ source: SourceImage, settings: DevelopSettings, quality: RenderQuality
    ) async throws -> DevelopedImage {
        let engine = self.engine
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(
                    with: Result { try Self.render(engine, source, settings, quality) })
            }
        }
    }

    private static func render(
        _ engine: Engine, _ source: SourceImage, _ settings: DevelopSettings,
        _ quality: RenderQuality
    ) throws -> DevelopedImage {
        let maxDimension: Int
        let format: PixelFormat
        switch quality {
        case .preview(let limit):
            maxDimension = max(0, limit)
            format = .rgbaF16
        case .full:
            maxDimension = 0
            format = .rgbaF32
        }
        let request = RenderRequest(
            film: settings.filmID,
            print: settings.paperID,
            paramsJson: try settings.enginePatchJSON(),
            color: RenderColor(input: .rec2020, output: .srgb),
            maxDimension: UInt32(maxDimension))
        let rendered = try engine.render(source: source, request: request)
        let width = Int(rendered.width())
        let height = Int(rendered.height())
        guard
            let cgImage = makeCGImage(
                pixels: rendered.pixels(format: format), width: width, height: height,
                format: format)
        else {
            throw SpektrafilmError.invalidEngineOutput
        }
        return DevelopedImage(
            cgImage: cgImage, width: width, height: height, stats: rendered.stats())
    }

    /// Wraps the engine's display-linear sRGB pixels in a `CGImage`.
    static func makeCGImage(pixels: Data, width: Int, height: Int, format: PixelFormat) -> CGImage? {
        let bitsPerComponent: Int
        let byteOrder: CGBitmapInfo
        switch format {
        case .rgbaF16:
            bitsPerComponent = 16
            byteOrder = .byteOrder16Little
        case .rgbaF32:
            bitsPerComponent = 32
            byteOrder = .byteOrder32Little
        }
        let bytesPerRow = width * bitsPerComponent / 2
        guard
            pixels.count == bytesPerRow * height,
            let provider = CGDataProvider(data: pixels as CFData),
            let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)
        else { return nil }
        // Alpha is always 1, so "premultiplied" changes nothing; it is the
        // float RGBA layout every CoreGraphics consumer accepts.
        let bitmapInfo: CGBitmapInfo = [
            .floatComponents, byteOrder,
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        ]
        return CGImage(
            width: width, height: height,
            bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerComponent * 4,
            bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
