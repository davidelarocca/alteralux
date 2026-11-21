import CoreImage
import Foundation
import ImageIO

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
    /// Whether the camera chose the white balance itself, from the scene (EXIF "auto"): the
    /// automatic white balance then keeps it, since the camera saw more than the photo shows.
    public nonisolated let cameraChoseWhiteBalance: Bool
    /// Whether this photo's lens can be corrected: its distortion, its darker corners and its
    /// colored fringes, by the RAW decoder from what the camera recorded, or with a lens profile.
    public nonisolated let correctsLens: Bool
    /// The lens profile that corrects this photo, where the RAW decoder does not know the lens:
    /// `nil` when the decoder does, or when no profile fits.
    public nonisolated let lensProfile: LensCorrection?
    /// Whether the RAW decoder corrects this photo's lens when it is not told: what adjustments
    /// saved without the choice get.
    public nonisolated let correctsLensByDefault: Bool

    private let rawFilter: CIRAWFilter?
    private let standardImage: CIImage?
    /// The white balance measured in the photo, once it was: `.some(nil)` when it could not be.
    private var measuredWhiteBalance: WhiteBalance??

    /// Opens `url`. Reads what the file says about itself, not its pixels.
    ///
    /// - Parameter lenses: the lens profiles to correct a RAW whose lens the decoder does not know.
    public init(url: URL, lenses: LensDatabase? = nil) throws {
        self.url = url
        isRaw = ImageLoader.isRawFile(url)
        let whole: CIImage
        if isRaw {
            let filter = try ImageLoader.rawFilter(for: url)
            asShotWhiteBalance = WhiteBalance(
                temperature: Double(filter.neutralTemperature), tint: Double(filter.neutralTint),
            )
            cameraChoseWhiteBalance = Self.cameraChoseWhiteBalance(of: url)
            correctsLensByDefault = filter.isLensCorrectionEnabled
            whole = try ImageLoader.rawImage(from: filter, url: url, maxDimension: nil, whiteBalance: nil)
            rawFilter = filter
            standardImage = nil
        } else {
            whole = try ImageLoader.standardImage(for: url)
            asShotWhiteBalance = nil
            cameraChoseWhiteBalance = false
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
        let decoderCorrects = rawFilter?.isLensCorrectionSupported ?? false
        lensProfile = decoderCorrects || !isRaw ? nil : lenses.flatMap { lenses in
            PhotoLensInfo.read(from: url).flatMap { info in
                lenses.lens(for: info)?.correction(for: info, imageWidth: Int(extent.width), imageHeight: Int(extent.height))
            }
        }
        correctsLens = decoderCorrects || lensProfile != nil
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

    /// The white balance an automatic choice gives this RAW: the camera's when the camera chose
    /// it itself, or when the light measured in the photo is close to it (see
    /// `AutomaticWhiteBalance`). Measured once, at the first call. `nil` for a file that is not a
    /// RAW.
    public func automaticWhiteBalance() -> WhiteBalance? {
        guard let rawFilter, let asShotWhiteBalance else { return nil }
        guard !cameraChoseWhiteBalance else { return asShotWhiteBalance }
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
            let correctsLens = lensCorrection ?? correctsLensByDefault
            image = try ImageLoader.rawImage(
                from: rawFilter, url: url, maxDimension: maxDimension,
                whiteBalance: whiteBalance ?? asShotWhiteBalance, lensCorrection: correctsLens,
            )
            .applyingLensProfile(correctsLens ? lensProfile : nil, fullSize: size)
        } else if let standardImage {
            image = ImageLoader.scaled(standardImage, maxDimension: maxDimension)
        } else {
            throw AlteraluxError.unreadableImage(url)
        }
        return try ImageLoader.pixels(of: crop.map { ImageLoader.framed(image, by: $0) } ?? image, url: url)
    }
}

extension PhotoDecoder {
    /// Whether the EXIF of `url` says the camera chose the white balance itself. A photo that does
    /// not say counts as one whose white balance was set by hand.
    static func cameraChoseWhiteBalance(of url: URL) -> Bool {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let mode = exif[kCGImagePropertyExifWhiteBalance] as? NSNumber
        else { return false }
        return mode.intValue == 0
    }
}

private extension CIImage {
    /// This image corrected with `profile`, or as it is for `nil`.
    func applyingLensProfile(_ profile: LensCorrection?, fullSize: CGSize) -> CIImage {
        profile.map { LensWarp.apply($0, to: self, fullSize: fullSize) } ?? self
    }
}
