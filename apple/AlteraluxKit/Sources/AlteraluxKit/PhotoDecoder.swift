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
    /// The correction made with what the camera recorded in the RAW: all of it where the RAW
    /// decoder does not know the lens, the vignetting alone where it does and leaves it (ADR 0015).
    /// `nil` when the file carries nothing that applies.
    public nonisolated let cameraLensCorrection: CameraLensCorrection?
    /// The lens profile that corrects this photo alone, where neither the RAW decoder nor the
    /// camera's own corrections do: `nil` when one of them does, or when no profile fits.
    public nonisolated let lensProfile: LensCorrection?
    /// What the RAW decoder offers this photo beyond white balance and lens (highlight recovery,
    /// noise reduction) and does when not told; `nil` for a file that is not a RAW.
    public nonisolated let rawDefaults: RawDecodingDefaults?
    /// Whether the RAW decoder corrects this photo's lens when it is not told: what adjustments
    /// saved without the choice get.
    public nonisolated let correctsLensByDefault: Bool

    private let rawFilter: CIRAWFilter?
    private let standardImage: CIImage?
    /// The white balance measured in the photo, once it was: `.some(nil)` when it could not be.
    private var measuredWhiteBalance: WhiteBalance??
    /// The exposure the engine's meter reads for the photo as it was shot, kept for the last
    /// way it was metered: every decode with the exposure automatic asks for it.
    private var metered: (method: MeteringMethod, stops: Double)?

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
            rawDefaults = RawDecodingDefaults(filter: filter)
            whole = try ImageLoader.rawImage(from: filter, url: url, maxDimension: nil, whiteBalance: nil)
            rawFilter = filter
            standardImage = nil
        } else {
            whole = try ImageLoader.standardImage(for: url)
            asShotWhiteBalance = nil
            cameraChoseWhiteBalance = false
            correctsLensByDefault = false
            rawDefaults = nil
            rawFilter = nil
            standardImage = whole
        }
        let extent = whole.extent.integral
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else {
            throw AlteraluxError.unreadableImage(url)
        }
        width = Int(extent.width)
        height = Int(extent.height)
        // The geometry by Apple's decoder, then by the camera, then by lensfun; the vignetting by the
        // camera, then by lensfun (ADR 0015).
        let decoderCorrects = rawFilter?.isLensCorrectionSupported ?? false
        let info = isRaw ? PhotoLensInfo.read(from: url) : nil
        let profile = decoderCorrects ? nil : info.flatMap { info in
            lenses?.lens(for: info)?.correction(for: info, imageWidth: Int(extent.width), imageHeight: Int(extent.height))
        }
        cameraLensCorrection = CameraLensCorrection.combining(
            camera: isRaw ? CameraLensData.read(from: url) : nil, lensfun: profile, appleCorrects: decoderCorrects,
            lensName: info.map { $0.lensModel.isEmpty ? $0.cameraModel : $0.lensModel } ?? "",
            size: SIMD2(Int(extent.width), Int(extent.height)),
        )
        lensProfile = cameraLensCorrection == nil ? profile : nil
        correctsLens = decoderCorrects || cameraLensCorrection != nil || lensProfile != nil
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
    /// `AutomaticWhiteBalance`). Measured once, at the first call, on the photo as it was shot
    /// (ADR 0022): whatever was decoded before it. `nil` for a file that is not a RAW.
    public func automaticWhiteBalance() -> WhiteBalance? {
        guard let rawFilter, let asShotWhiteBalance else { return nil }
        guard !cameraChoseWhiteBalance else { return asShotWhiteBalance }
        if let measuredWhiteBalance {
            return measuredWhiteBalance ?? asShotWhiteBalance
        }
        // The decoder is kept between decodes: the last one may have left it with the
        // adjustments' own highlight recovery, noise reduction and lens correction.
        rawDefaults?.apply(RawDecodingOptions(), to: rawFilter)
        if rawFilter.isLensCorrectionSupported {
            rawFilter.isLensCorrectionEnabled = correctsLensByDefault
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
            crop: settings.crop, rawDecoding: settings.rawDecoding, sceneTone: SceneToneRequest(settings),
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
    ///   - rawDecoding: the RAW decoder's highlight recovery and noise reduction. Ignored for other
    ///     files.
    ///   - sceneTone: the meter's exposure and the scene's highlights and shadows, to put into
    ///     the pixels; `nil` to leave the scene as it is. With the meter on, the result holds the
    ///     exposure the meter reads for the photo as it was shot (`LoadedImage.isMetered`).
    public nonisolated func decode(
        maxDimension: Int? = nil, whiteBalance: WhiteBalance? = nil, lensCorrection: Bool? = nil,
        crop: PhotoCrop? = nil, rawDecoding: RawDecodingOptions = .init(), sceneTone: SceneToneRequest? = nil,
    ) async throws -> LoadedImage {
        let limit = maxDimension.flatMap { $0 > 0 ? $0 : nil }
        let pixels = try await pixels(
            maxDimension: limit, whiteBalance: whiteBalance, lensCorrection: lensCorrection, crop: crop,
            rawDecoding: rawDecoding, sceneTone: sceneTone,
        )
        // Handing the pixels to the engine copies them: not while holding the decoder.
        return try pixels.loaded(from: url, isRaw: isRaw)
    }

    /// The pixels out of Core Image, before they are handed to the engine.
    func pixels(
        maxDimension: Int?, whiteBalance: WhiteBalance?, lensCorrection: Bool? = nil, crop: PhotoCrop? = nil,
        rawDecoding: RawDecodingOptions = .init(), sceneTone: SceneToneRequest? = nil,
    ) throws -> DecodedPixels {
        // The meter reads the photo as it was shot, so it comes first: it decodes the photo
        // small, with the same decoder, which the decode after it sets as the adjustments ask.
        var meteredStops: Double?
        if let sceneTone, SceneToneKernel.isAvailable, let method = sceneTone.meteringMethod {
            meteredStops = try self.meteredStops(method)
        }
        let image = try image(
            maxDimension: maxDimension, whiteBalance: whiteBalance, lensCorrection: lensCorrection, crop: crop,
            rawDecoding: rawDecoding,
        )
        guard
            let sceneTone,
            let lit = SceneToneKernel.apply(
                sceneTone.tone, to: image, meteredEV: meteredStops ?? 0, exposureEV: sceneTone.exposureEV,
            )
        else { return try ImageLoader.pixels(of: image, url: url) }
        var pixels = try ImageLoader.pixels(of: lit, url: url)
        pixels.isMetered = meteredStops != nil
        return pixels
    }

    /// The photo as Core Image decodes it: with its white balance, its lens corrected, framed.
    private func image(
        maxDimension: Int?, whiteBalance: WhiteBalance?, lensCorrection: Bool?, crop: PhotoCrop?,
        rawDecoding: RawDecodingOptions,
    ) throws -> CIImage {
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
            rawDefaults?.apply(rawDecoding, to: rawFilter)
            let correctsLens = lensCorrection ?? correctsLensByDefault
            image = try ImageLoader.rawImage(
                from: rawFilter, url: url, maxDimension: maxDimension,
                whiteBalance: whiteBalance ?? asShotWhiteBalance, lensCorrection: correctsLens,
            )
            .applyingLensCorrection(
                camera: correctsLens ? cameraLensCorrection : nil, profile: correctsLens ? lensProfile : nil,
                fullSize: size,
            )
        } else if let standardImage {
            image = ImageLoader.scaled(standardImage, maxDimension: maxDimension)
        } else {
            throw AlteraluxError.unreadableImage(url)
        }
        return crop.map { ImageLoader.framed(image, by: $0) } ?? image
    }

    /// The stops the engine's meter adds to the photo, read by the engine itself on the photo
    /// decoded small: what a render with the meter on adds before the film, whatever the exposure
    /// compensation. Of `settings` only the metering method counts: the meter reads the photo as
    /// it was shot, not as they frame it or balance it (ADR 0022).
    public func meteredExposure(settings: DevelopSettings) throws -> Double {
        try meteredStops(settings.meteringMethod)
    }

    /// The long side the photo is decoded at to be metered: the engine's meter reads a picture
    /// no larger than this, taking one pixel in so many of a larger one.
    static let meteringSide = 256

    /// The stops the engine's meter adds to the photo as it was shot, read by the engine itself
    /// on the photo decoded small: whole, with the camera's white balance, the lens corrected as
    /// it is when nothing was chosen, and the RAW decoder's own choices.
    private func meteredStops(_ method: MeteringMethod) throws -> Double {
        if let metered, metered.method == method {
            return metered.stops
        }
        let small = try ImageLoader.pixels(
            of: image(
                maxDimension: Self.meteringSide, whiteBalance: nil, lensCorrection: nil, crop: nil,
                rawDecoding: RawDecodingOptions(),
            ),
            url: url,
        )
        let stops = try Double(small.loaded(from: url, isRaw: isRaw).source.meteredEv(method: method.rawValue, input: .rec2020))
        metered = (method, stops)
        return stops
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
    /// This image corrected with the camera's curves or with `profile`, or as it is for `nil`.
    func applyingLensCorrection(camera: CameraLensCorrection?, profile: LensCorrection?, fullSize: CGSize) -> CIImage {
        if let camera {
            return LensWarp.apply(camera, to: self, fullSize: fullSize)
        }
        return profile.map { LensWarp.apply($0, to: self, fullSize: fullSize) } ?? self
    }
}
