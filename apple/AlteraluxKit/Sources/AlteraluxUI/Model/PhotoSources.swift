import AlteraluxKit
import Foundation

/// The selected photo as the engine gets it: decoded when asked, at the size, with the white
/// balance and with the frame asked, and kept for as long as it can be used again.
///
/// A preview is decoded at its own size, which takes a fraction of the time of the whole photo;
/// the whole photo is decoded for the 100% view and for export. One of these exists per selected
/// photo: selecting another photo lets go of everything decoded for this one.
@MainActor
final class PhotoSources {
    let decoder: PhotoDecoder

    /// How many reduced sizes are kept: the lighter preview, the standard one and the one the
    /// viewer needs. At 2048 px one is about 33 MB.
    static let keptSizes = 3
    /// How long after the lighter preview the whole photo is decoded ahead of need. Decoding it
    /// keeps the decoder busy for some tenths of a second, so it waits for a quiet moment.
    static let wholePhotoDelay = Duration.seconds(1)

    /// What the pixels kept were decoded with, apart from their size.
    private struct Decoding: Equatable {
        var whiteBalance: WhiteBalance?
        var lensCorrection: Bool?
        var crop: PhotoCrop?
        var rawDecoding = RawDecodingOptions()
    }

    /// The white balance, the lens correction and the frame of what is kept. A change of any
    /// makes all of it useless.
    private var kind = Decoding()
    /// Counts the changes of white balance or frame, to tell a decode that ends after one.
    private var epoch = 0
    private var whole: LoadedImage?
    /// The reduced sizes, the latest used first.
    private var reduced: [(dimension: Int, image: LoadedImage)] = []
    private var decoding: [Int: Task<LoadedImage, any Error>] = [:]
    private var preparation: Task<Void, Never>?
    /// The white balance and the frame of what is being decoded ahead.
    private var preparedKind: Decoding?
    /// The automatic white balance of the photo, once the decoder measured it.
    private(set) var automaticWhiteBalance: WhiteBalance?
    private var hasMeasuredWhiteBalance = false

    init(decoder: PhotoDecoder) {
        self.decoder = decoder
    }

    /// The long side of the photo framed by `crop`, in pixels.
    func longSide(framedBy crop: PhotoCrop?) -> Int {
        decoder.longSide(framedBy: crop)
    }

    /// What `settings` ask to decode, apart from the size.
    private func kind(for settings: DevelopSettings) -> Decoding {
        Decoding(
            whiteBalance: whiteBalance(for: settings), lensCorrection: settings.lensCorrection,
            crop: settings.crop.flatMap { $0.isWhole ? nil : $0 }, rawDecoding: settings.rawDecoding,
        )
    }

    /// The white balance `settings` give this photo: `nil` when it is not a RAW. The automatic
    /// one is known only once ``measureWhiteBalance()`` has measured it.
    func whiteBalance(for settings: DevelopSettings) -> WhiteBalance? {
        let automatic = settings.autoWhiteBalance ? automaticWhiteBalance : nil
        return decoder.asShotWhiteBalance.map { settings.whiteBalance(asShot: $0, automatic: automatic) }
    }

    /// Measures the photo's automatic white balance, once.
    @discardableResult
    func measureWhiteBalance() async -> WhiteBalance? {
        if !hasMeasuredWhiteBalance {
            automaticWhiteBalance = await decoder.automaticWhiteBalance()
            hasMeasuredWhiteBalance = true
        }
        return automaticWhiteBalance
    }

    /// The photo decoded for `settings`.
    ///
    /// - Parameter dimension: the long side, in pixels; 0, or anything not smaller than the
    ///   framed photo, for the whole of it.
    func source(dimension: Int, settings: DevelopSettings) async throws -> LoadedImage {
        if settings.autoWhiteBalance {
            await measureWhiteBalance()
        }
        let wanted = kind(for: settings)
        let framedLongSide = longSide(framedBy: wanted.crop)
        let dimension = dimension <= 0 || dimension >= framedLongSide ? 0 : dimension
        if wanted != kind {
            kind = wanted
            epoch += 1
            whole = nil
            reduced.removeAll()
            decoding.removeAll()
        }
        if let kept = kept(dimension) {
            return kept
        }
        if let running = decoding[dimension] {
            return try await running.value
        }
        let decoder = decoder
        let task = Task {
            try await decoder.decode(
                maxDimension: dimension, whiteBalance: wanted.whiteBalance, lensCorrection: wanted.lensCorrection,
                crop: wanted.crop, rawDecoding: wanted.rawDecoding,
            )
        }
        decoding[dimension] = task
        let started = epoch
        defer {
            if epoch == started {
                decoding[dimension] = nil
            }
        }
        let image = try await task.value
        if epoch == started {
            keep(image, dimension: dimension)
        }
        return image
    }

    /// Decodes ahead of need what the next moves will ask for: the lighter preview at once, so
    /// the first move of a control does not wait for it, and the whole photo after a while, for
    /// the 100% view and for export.
    func prepare(lighterDimension: Int, settings: DevelopSettings) {
        guard preparation == nil else { return }
        preparedKind = kind(for: settings)
        preparation = Task { [weak self] in
            _ = try? await self?.source(dimension: lighterDimension, settings: settings)
            try? await Task.sleep(for: Self.wholePhotoDelay)
            if !Task.isCancelled {
                _ = try? await self?.source(dimension: 0, settings: settings)
            }
            if !Task.isCancelled {
                self?.preparation = nil
            }
        }
    }

    /// Stops decoding ahead when `settings` ask for another white balance, lens correction or frame: what
    /// was being decoded is of no use, and the decoder must be free for the new one. Any other
    /// change leaves it going, since it decodes the same pixels.
    func settingsDidChange(_ settings: DevelopSettings) {
        guard preparation != nil, kind(for: settings) != preparedKind else { return }
        preparation?.cancel()
        preparation = nil
    }

    private func kept(_ dimension: Int) -> LoadedImage? {
        guard dimension > 0 else { return whole }
        guard let index = reduced.firstIndex(where: { $0.dimension == dimension }) else { return nil }
        let entry = reduced.remove(at: index)
        reduced.insert(entry, at: 0)
        return entry.image
    }

    private func keep(_ image: LoadedImage, dimension: Int) {
        guard dimension > 0 else {
            whole = image
            return
        }
        reduced.removeAll { $0.dimension == dimension }
        reduced.insert((dimension, image), at: 0)
        if reduced.count > Self.keptSizes {
            reduced.removeLast(reduced.count - Self.keptSizes)
        }
    }
}
