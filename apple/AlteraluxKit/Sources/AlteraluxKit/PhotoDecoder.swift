import CoreImage
import Foundation

/// Decodes one photo as many times as the app needs it: at the size of each preview, at its
/// own size for the 100% view and for export, and for a RAW with the white balance chosen.
///
/// It keeps the RAW decoder between calls, so a change of white balance does not start from the
/// file again, and it has the decoder scale the photo: a preview is decoded in a fraction of
/// the time of the whole photo. One decode runs at a time.
public actor PhotoDecoder {
    public nonisolated let url: URL
    /// `true` when the file is a camera RAW decoded with Apple's RAW engine.
    public nonisolated let isRaw: Bool
    /// The size of the whole photo, in pixels, as it is shown (rotated as the camera says).
    public nonisolated let width: Int
    public nonisolated let height: Int
    /// The white balance the camera recorded. `nil` for a file that is not a RAW: its white
    /// balance is in its pixels and cannot be chosen again.
    public nonisolated let asShotWhiteBalance: WhiteBalance?

    private let rawFilter: CIRAWFilter?
    private let standardImage: CIImage?

    /// Opens `url`. Reads what the file says about itself, not its pixels.
    public init(url: URL) throws {
        self.url = url
        isRaw = ImageLoader.isRawFile(url)
        let whole: CIImage
        if isRaw {
            let filter = try ImageLoader.rawFilter(for: url)
            asShotWhiteBalance = WhiteBalance(
                temperature: Double(filter.neutralTemperature), tint: Double(filter.neutralTint),
            )
            whole = try ImageLoader.rawImage(from: filter, url: url, maxDimension: nil, whiteBalance: nil)
            rawFilter = filter
            standardImage = nil
        } else {
            whole = try ImageLoader.standardImage(for: url)
            asShotWhiteBalance = nil
            rawFilter = nil
            standardImage = whole
        }
        let extent = whole.extent.integral
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else {
            throw AlteraluxError.unreadableImage(url)
        }
        width = Int(extent.width)
        height = Int(extent.height)
    }

    /// Decodes the photo.
    ///
    /// - Parameters:
    ///   - maxDimension: the long side of the result, in pixels; `nil` or 0 for the whole photo.
    ///   - whiteBalance: what to take as neutral in a RAW; `nil` for what the camera recorded.
    ///     Ignored for other files.
    public nonisolated func decode(
        maxDimension: Int? = nil, whiteBalance: WhiteBalance? = nil,
    ) async throws -> LoadedImage {
        let limit = maxDimension.flatMap { $0 > 0 ? $0 : nil }
        let pixels = try await pixels(maxDimension: limit, whiteBalance: whiteBalance)
        // Handing the pixels to the engine copies them: not while holding the decoder.
        return try pixels.loaded(from: url, isRaw: isRaw)
    }

    /// The pixels out of Core Image, before they are handed to the engine.
    func pixels(maxDimension: Int?, whiteBalance: WhiteBalance?) throws -> DecodedPixels {
        let image: CIImage
        if let rawFilter {
            image = try ImageLoader.rawImage(
                from: rawFilter, url: url, maxDimension: maxDimension,
                whiteBalance: whiteBalance ?? asShotWhiteBalance,
            )
        } else if let standardImage {
            image = ImageLoader.scaled(standardImage, maxDimension: maxDimension)
        } else {
            throw AlteraluxError.unreadableImage(url)
        }
        return try ImageLoader.pixels(of: image, url: url)
    }
}
