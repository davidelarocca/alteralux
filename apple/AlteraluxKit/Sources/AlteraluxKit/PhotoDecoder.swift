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
    /// Whether the RAW decoder knows how to correct this photo's lens: its distortion, its
    /// darker corners and its colored fringes, from what the camera recorded.
    public nonisolated let correctsLens: Bool
    /// Whether the RAW decoder corrects this photo's lens when it is not told: what adjustments
    /// saved without the choice get.
    public nonisolated let correctsLensByDefault: Bool

    private let rawFilter: CIRAWFilter?
    private let standardImage: CIImage?
    /// The white balance measured in the photo, once it was: `.some(nil)` when it could not be.
    private var measuredWhiteBalance: WhiteBalance??

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
            correctsLens = filter.isLensCorrectionSupported
            correctsLensByDefault = filter.isLensCorrectionEnabled
            whole = try ImageLoader.rawImage(from: filter, url: url, maxDimension: nil, whiteBalance: nil)
            rawFilter = filter
            standardImage = nil
        } else {
            whole = try ImageLoader.standardImage(for: url)
            asShotWhiteBalance = nil
            correctsLens = false
            correctsLensByDefault = false
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

    /// The size of the whole photo, in pixels.
    public nonisolated var size: CGSize {
        CGSize(width: width, height: height)
    }

    /// The long side of the photo framed by `crop`, in pixels: the whole photo's for `nil`.
    public nonisolated func longSide(framedBy crop: PhotoCrop?) -> Int {
        guard let crop else { return max(width, height) }
        let framed = crop.framedSize(of: size)
        return max(1, Int(max(framed.width, framed.height).rounded()))
    }

    /// The white balance an automatic choice gives this RAW: the camera's, unless the light
    /// measured in the photo is far from it (see `AutomaticWhiteBalance`). Measured once, at the
    /// first call. `nil` for a file that is not a RAW.
    public func automaticWhiteBalance() -> WhiteBalance? {
        guard let rawFilter, let asShotWhiteBalance else { return nil }
        if let measuredWhiteBalance {
            return measuredWhiteBalance ?? asShotWhiteBalance
        }
        let measured = AutomaticWhiteBalance.whiteBalance(of: rawFilter, asShot: asShotWhiteBalance)
        measuredWhiteBalance = .some(measured)
        return measured ?? asShotWhiteBalance
    }

    /// The white balance `settings` give this photo: the one chosen, the automatic one, or the
    /// camera's. `nil` for a file that is not a RAW.
    public func whiteBalance(for settings: DevelopSettings) -> WhiteBalance? {
        guard let asShotWhiteBalance else { return nil }
        let automatic = settings.autoWhiteBalance ? automaticWhiteBalance() : nil
        return settings.whiteBalance(asShot: asShotWhiteBalance, automatic: automatic)
    }

    /// Decodes the photo as `settings` ask: with their white balance, lens correction and frame.
    ///
    /// - Parameter maxDimension: the long side of the framed result, in pixels; `nil` or 0 for
    ///   the whole photo.
    public func decode(maxDimension: Int? = nil, settings: DevelopSettings) async throws -> LoadedImage {
        let whiteBalance = whiteBalance(for: settings)
        return try await decode(
            maxDimension: maxDimension, whiteBalance: whiteBalance, lensCorrection: settings.lensCorrection,
            crop: settings.crop,
        )
    }

    /// Decodes the photo.
    ///
    /// - Parameters:
    ///   - maxDimension: the long side of the result, in pixels; `nil` or 0 for the whole photo.
    ///   - whiteBalance: what to take as neutral in a RAW; `nil` for what the camera recorded.
    ///     Ignored for other files.
    ///   - lensCorrection: whether to correct the lens, where the RAW decoder knows how; `nil`
    ///     for what the decoder does on its own.
    ///   - crop: how to straighten and cut the photo; `nil` for the whole of it. `maxDimension`
    ///     is then the long side of the framed picture.
    public nonisolated func decode(
        maxDimension: Int? = nil, whiteBalance: WhiteBalance? = nil, lensCorrection: Bool? = nil,
        crop: PhotoCrop? = nil,
    ) async throws -> LoadedImage {
        let limit = maxDimension.flatMap { $0 > 0 ? $0 : nil }
        let pixels = try await pixels(
            maxDimension: limit, whiteBalance: whiteBalance, lensCorrection: lensCorrection, crop: crop,
        )
        // Handing the pixels to the engine copies them: not while holding the decoder.
        return try pixels.loaded(from: url, isRaw: isRaw)
    }

    /// The pixels out of Core Image, before they are handed to the engine.
    func pixels(
        maxDimension: Int?, whiteBalance: WhiteBalance?, lensCorrection: Bool? = nil, crop: PhotoCrop? = nil,
    ) throws -> DecodedPixels {
        let crop = crop.flatMap { $0.isWhole ? nil : $0 }
        // The whole photo is decoded at the size that gives the framed picture the size asked.
        let framedLongSide = longSide(framedBy: crop)
        let maxDimension = maxDimension.flatMap { limit -> Int? in
            guard limit < framedLongSide else { return nil }
            let whole = Double(limit) * Double(max(width, height)) / Double(framedLongSide)
            return Int(whole.rounded(.up))
        }
        let image: CIImage
        if let rawFilter {
            image = try ImageLoader.rawImage(
                from: rawFilter, url: url, maxDimension: maxDimension,
                whiteBalance: whiteBalance ?? asShotWhiteBalance,
                lensCorrection: lensCorrection ?? correctsLensByDefault,
            )
        } else if let standardImage {
            image = ImageLoader.scaled(standardImage, maxDimension: maxDimension)
        } else {
            throw AlteraluxError.unreadableImage(url)
        }
        return try ImageLoader.pixels(of: crop.map { ImageLoader.framed(image, by: $0) } ?? image, url: url)
    }
}
