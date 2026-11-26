import CoreGraphics
import Foundation

/// Small images of photos developed with their adjustments, for the library's grid and the
/// strip, kept in memory and on disk.
///
/// A thumbnail is known by the file it was made from (its path, size and date), the
/// adjustments, the film model and its size: change any of them and it is made again. Making
/// one decodes the photo small and develops it with the app's one renderer: about a quarter of
/// a second for a 24-megapixel RAW, nearly all of it the decoding, which runs outside the
/// renderer, so the engine is busy some 20 ms for each and the photo being developed hardly
/// waits. Only a few are made at once.
public actor DevelopedThumbnails {
    /// What a thumbnail is made from.
    public struct Request: Sendable {
        public let photo: URL
        public let settings: DevelopSettings
        public let maxDimension: Int

        public init(photo: URL, settings: DevelopSettings, maxDimension: Int) {
            self.photo = photo
            self.settings = settings
            self.maxDimension = maxDimension
        }
    }

    /// Change it when what the app does around the engine changes how a thumbnail looks.
    private static let revision = "d1"
    /// Keep 256 images so a visit to a large folder cannot grow thumbnail memory without limit.
    private static let memoryLimit = 256

    private let cacheDirectory: URL?
    private let concurrency: Int
    private var memory: [String: SendableCGImage] = [:]
    private var memoryOrder: [String] = []
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// How many thumbnails were developed, not found kept: for the tests.
    private(set) var developedCount = 0

    /// - Parameters:
    ///   - cacheDirectory: where thumbnails are kept between launches; `nil` keeps none on disk.
    ///   - concurrency: how many photos are decoded and developed at once.
    public init(cacheDirectory: URL?, concurrency: Int = 2) {
        self.cacheDirectory = cacheDirectory?.standardizedFileURL
        self.concurrency = max(1, concurrency)
    }

    /// The thumbnail when it is already made, in memory or on disk; `nil` otherwise, at once.
    public func kept(_ request: Request) async -> CGImage? {
        guard let key = Self.key(for: request) else { return nil }
        return await keptImage(key)?.image
    }

    /// The thumbnail, made now when it is not kept. `nil` when the photo cannot be decoded or
    /// developed, or when the task asking for it is cancelled before its turn.
    public func thumbnail(
        _ request: Request, renderer: FilmRenderer, lenses: LensDatabase? = nil,
    ) async -> CGImage? {
        guard request.maxDimension > 0, let key = Self.key(for: request) else { return nil }
        if let image = await keptImage(key) {
            return image.image
        }
        await takeTurn()
        defer { endTurn() }
        // Asked by a tile that has since left the screen, or made meanwhile by another request.
        guard !Task.isCancelled else { return nil }
        if let image = memory[key] {
            touch(key)
            return image.image
        }
        let developed = await Task.detached(priority: .utility) {
            await Self.develop(request, renderer: renderer, lenses: lenses)
        }.value
        guard let developed else { return nil }
        developedCount += 1
        remember(developed, key: key)
        if let cacheDirectory {
            let file = cacheDirectory.appending(path: "\(key).jpg")
            Task.detached(priority: .background) {
                try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                try? ThumbnailFiles.jpegData(of: developed.image)?.write(to: file, options: .atomic)
            }
        }
        return developed.image
    }

    /// Keeps the thumbnails on disk under `limit` bytes, removing the ones written longest ago.
    /// Synchronous: call it off the main thread.
    public nonisolated func pruneDiskCache(toAtMost limit: Int64) {
        guard let cacheDirectory else { return }
        ThumbnailFiles.prune(cacheDirectory, toAtMost: limit)
    }

    // MARK: - Private

    private func keptImage(_ key: String) async -> SendableCGImage? {
        if let image = memory[key] {
            touch(key)
            return image
        }
        guard let cacheDirectory else { return nil }
        let file = cacheDirectory.appending(path: "\(key).jpg")
        let read = await Task.detached(priority: .userInitiated) {
            ThumbnailFiles.read(file).map(SendableCGImage.init)
        }.value
        if let read {
            remember(read, key: key)
        }
        return read
    }

    private func takeTurn() async {
        if running < concurrency {
            running += 1
            return
        }
        // The turn is handed over by `endTurn`, which leaves `running` as it is.
        await withCheckedContinuation { waiting.append($0) }
    }

    private func endTurn() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    private func remember(_ image: SendableCGImage, key: String) {
        memory[key] = image
        touch(key)
    }

    private func touch(_ key: String) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
        while memoryOrder.count > Self.memoryLimit {
            memory.removeValue(forKey: memoryOrder.removeFirst())
        }
    }

    private static func key(for request: Request) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let file = ThumbnailFiles.identity(of: request.photo.standardizedFileURL),
              let encoded = try? encoder.encode(request.settings),
              let settings = String(bytes: encoded, encoding: .utf8)
        else { return nil }
        let identity = [
            revision, FilmModel.version, file, String(request.maxDimension),
            settings,
        ].joined(separator: "|")
        return ThumbnailFiles.stableHash(identity)
    }

    private static func develop(
        _ request: Request, renderer: FilmRenderer, lenses: LensDatabase?,
    ) async -> SendableCGImage? {
        let settings = request.settings
        guard let decoder = try? PhotoDecoder(url: request.photo, lenses: lenses),
              let loaded = try? await decoder.decode(maxDimension: request.maxDimension, settings: settings),
              let image = try? await renderer.render(
                  loaded, settings: settings, quality: .preview(maxDimension: request.maxDimension),
                  photoLongSide: decoder.longSide(framedBy: settings.crop),
              )
        else { return nil }
        return SendableCGImage(image.cgImage)
    }
}

/// Carries an immutable `CGImage` across tasks.
private final class SendableCGImage: @unchecked Sendable { // concurrency: CGImage is immutable once created
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
