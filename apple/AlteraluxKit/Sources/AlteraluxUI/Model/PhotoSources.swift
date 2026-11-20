import AlteraluxKit
import Foundation

/// The selected photo as the engine gets it: decoded when asked, at the size and with the white
/// balance asked, and kept for as long as it can be used again.
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

    /// The white balance of what is kept. A change of it makes all of that useless.
    private var whiteBalance: WhiteBalance?
    /// Counts the changes of white balance, to tell a decode that ends after one.
    private var epoch = 0
    private var whole: LoadedImage?
    /// The reduced sizes, the latest used first.
    private var reduced: [(dimension: Int, image: LoadedImage)] = []
    private var decoding: [Int: Task<LoadedImage, any Error>] = [:]
    private var preparation: Task<Void, Never>?
    /// The white balance of what is being decoded ahead.
    private var preparedWhiteBalance: WhiteBalance?

    init(decoder: PhotoDecoder) {
        self.decoder = decoder
    }

    /// The long side of the whole photo, in pixels.
    var longSide: Int {
        max(decoder.width, decoder.height)
    }

    /// The white balance `settings` give this photo: `nil` when it is not a RAW.
    func whiteBalance(for settings: DevelopSettings) -> WhiteBalance? {
        decoder.asShotWhiteBalance.map { settings.whiteBalance(asShot: $0) }
    }

    /// The photo decoded for `settings`.
    ///
    /// - Parameter dimension: the long side, in pixels; 0, or anything not smaller than the
    ///   photo, for the whole of it.
    func source(dimension: Int, settings: DevelopSettings) async throws -> LoadedImage {
        let dimension = dimension <= 0 || dimension >= longSide ? 0 : dimension
        let whiteBalance = whiteBalance(for: settings)
        if whiteBalance != self.whiteBalance {
            self.whiteBalance = whiteBalance
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
            try await decoder.decode(maxDimension: dimension, whiteBalance: whiteBalance)
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
        preparedWhiteBalance = whiteBalance(for: settings)
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

    /// Stops decoding ahead when `settings` ask for another white balance: what was being
    /// decoded is of no use, and the decoder must be free for the new one. Any other change
    /// leaves it going, since it decodes the same pixels.
    func settingsDidChange(_ settings: DevelopSettings) {
        guard preparation != nil, whiteBalance(for: settings) != preparedWhiteBalance else { return }
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
