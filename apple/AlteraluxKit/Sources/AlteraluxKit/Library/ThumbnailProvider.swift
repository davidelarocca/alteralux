import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes small, upright library images and keeps them for later requests.
public actor ThumbnailProvider {
    private struct RequestKey: Hashable {
        let path: String
        let maxDimension: Int

        var value: String {
            "\(Data(path.utf8).base64EncodedString())|\(maxDimension)"
        }
    }

    private struct Waiter {
        let continuation: CheckedContinuation<SendableCGImage?, Never>
    }

    private struct PendingRequest {
        let identity: String
        let request: RequestKey
        let url: URL
        let maxDimension: Int
        let waiterID: UUID
        let continuation: CheckedContinuation<SendableCGImage?, Never>
    }

    private struct Work {
        let identity: String
        let request: RequestKey
        let url: URL
        let maxDimension: Int
        let epoch: UInt64
        var waiters: [UUID: Waiter]
        var isRunning = false
        var task: Task<Void, Never>?
    }

    private struct WorkResult: Sendable {
        let image: SendableCGImage?
        let decodedSource: Bool
    }

    private final class SendableCGImage: @unchecked Sendable { // concurrency: CGImage is immutable once created
        let image: CGImage

        init(_ image: CGImage) {
            self.image = image
        }
    }

    private let cacheDirectory: URL?
    private let concurrency: Int
    /// Keep 256 images so a visit to a large folder cannot grow thumbnail memory without limit.
    private let memoryLimit = 256
    private var memory: [String: SendableCGImage] = [:]
    private var memoryOrder: [String] = []
    private var latestIdentityByRequest: [RequestKey: String] = [:]
    private var requestOrder: [RequestKey] = []
    private var work: [String: Work] = [:]
    private var pending: [String] = []
    private var pendingDiskWrites: [UUID: Task<Void, Never>] = [:]
    private var epoch: UInt64 = 0
    private var isClearing = false

    private(set) var activeDecodeCount = 0
    private(set) var highWaterMark = 0
    private(set) var decodeCount = 0

    /// Creates a provider that keeps at most four concurrent decodes by default.
    /// Set `cacheDirectory` to keep JPEG thumbnails between launches.
    public init(cacheDirectory: URL?, concurrency: Int = 4) {
        self.cacheDirectory = cacheDirectory?.standardizedFileURL
        self.concurrency = max(1, concurrency)
    }

    /// Returns the file's thumbnail, applying its orientation and preserving its proportions.
    public nonisolated func thumbnail(for url: URL, maxDimension: Int) async -> CGImage? {
        let result = await requestThumbnail(for: url, maxDimension: maxDimension)
        return result?.image
    }

    /// Keeps the thumbnails on disk under `limit` bytes, removing the ones written longest ago.
    /// A thumbnail removed is made again when it is next asked for. Synchronous: call it off the
    /// main thread.
    public nonisolated func pruneDiskCache(toAtMost limit: Int64) {
        guard let cacheDirectory else { return }
        ThumbnailFiles.prune(cacheDirectory, toAtMost: limit)
    }

    /// Removes all cached images and waits for outstanding cache writes to finish.
    public func removeAll() async {
        isClearing = true
        epoch &+= 1
        memory.removeAll()
        memoryOrder.removeAll()
        latestIdentityByRequest.removeAll()
        requestOrder.removeAll()
        pending.removeAll()

        var runningTasks: [Task<Void, Never>] = []
        for key in Array(work.keys) {
            guard var item = work[key] else { continue }
            for waiter in item.waiters.values {
                waiter.continuation.resume(returning: nil)
            }
            item.waiters.removeAll()
            if item.isRunning {
                item.task?.cancel()
                if let task = item.task {
                    runningTasks.append(task)
                }
                work[key] = item
            } else {
                work.removeValue(forKey: key)
            }
        }

        for task in runningTasks {
            await task.value
        }

        let writes = Array(pendingDiskWrites.values)
        for task in writes {
            task.cancel()
        }
        for task in writes {
            await task.value
        }

        if let cacheDirectory, FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        isClearing = false
    }

    /// Lets the tests wait until the intentionally asynchronous disk writes have settled.
    func waitForDiskWrites() async {
        while let task = pendingDiskWrites.values.first {
            await task.value
        }
    }

    private func requestThumbnail(for url: URL, maxDimension: Int) async -> SendableCGImage? {
        guard maxDimension > 0, !Task.isCancelled, !isClearing, url.isFileURL else { return nil }

        let standardizedURL = url.standardizedFileURL
        let request = RequestKey(path: standardizedURL.path, maxDimension: maxDimension)
        let identity: String

        if let fileIdentity = fileIdentity(for: standardizedURL, maxDimension: maxDimension) {
            identity = fileIdentity
        } else if let rememberedIdentity = latestIdentityByRequest[request], memory[rememberedIdentity] != nil {
            identity = rememberedIdentity
        } else if let diskIdentity = identityFromDiskIndex(for: request) {
            identity = diskIdentity
        } else {
            return nil
        }

        if let image = memory[identity] {
            touchMemory(identity)
            return image
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            if Task.isCancelled {
                return nil
            }
            return await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    enqueue(PendingRequest(
                        identity: identity,
                        request: request,
                        url: standardizedURL,
                        maxDimension: maxDimension,
                        waiterID: waiterID,
                        continuation: continuation,
                    ))
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(identity: identity, waiterID: waiterID)
            }
        }
    }

    private func enqueue(_ request: PendingRequest) {
        let waiter = Waiter(continuation: request.continuation)
        if var existing = work[request.identity] {
            existing.waiters[request.waiterID] = waiter
            work[request.identity] = existing
            return
        }

        work[request.identity] = Work(
            identity: request.identity,
            request: request.request,
            url: request.url,
            maxDimension: request.maxDimension,
            epoch: epoch,
            waiters: [request.waiterID: waiter],
        )
        pending.append(request.identity)
        startPendingWork()
    }

    private func cancelWaiter(identity: String, waiterID: UUID) {
        guard var item = work[identity], let waiter = item.waiters.removeValue(forKey: waiterID) else { return }
        waiter.continuation.resume(returning: nil)
        if item.waiters.isEmpty, !item.isRunning {
            work.removeValue(forKey: identity)
            pending.removeAll { $0 == identity }
        } else {
            work[identity] = item
        }
    }

    private func startPendingWork() {
        guard !isClearing else { return }
        while activeDecodeCount < concurrency, !pending.isEmpty {
            let identity = pending.removeFirst()
            guard var item = work[identity], !item.waiters.isEmpty else {
                work.removeValue(forKey: identity)
                continue
            }

            item.isRunning = true
            activeDecodeCount += 1
            highWaterMark = max(highWaterMark, activeDecodeCount)

            let cacheDirectory = cacheDirectory
            let url = item.url
            let maxDimension = item.maxDimension
            let workEpoch = item.epoch
            let task = Task.detached(priority: .userInitiated) {
                let result = Self.loadOrCreateThumbnail(
                    at: url,
                    identity: identity,
                    maxDimension: maxDimension,
                    cacheDirectory: cacheDirectory,
                )
                await self.finishWork(identity: identity, epoch: workEpoch, result: result)
            }
            item.task = task
            work[identity] = item
        }
    }

    private func finishWork(identity: String, epoch workEpoch: UInt64, result: WorkResult) {
        activeDecodeCount = max(0, activeDecodeCount - 1)
        guard let item = work.removeValue(forKey: identity) else {
            startPendingWork()
            return
        }

        if item.epoch == epoch, workEpoch == epoch, let image = result.image {
            decodeCount += result.decodedSource ? 1 : 0
            remember(image, identity: identity, request: item.request)
            if result.decodedSource {
                beginDiskWrite(image, identity: identity, request: item.request)
            }
        }

        for waiter in item.waiters.values {
            waiter.continuation.resume(returning: item.epoch == epoch ? result.image : nil)
        }
        startPendingWork()
    }

    private func remember(_ image: SendableCGImage, identity: String, request: RequestKey) {
        memory[identity] = image
        touchMemory(identity)
        latestIdentityByRequest[request] = identity
        requestOrder.removeAll { $0 == request }
        requestOrder.append(request)
        while requestOrder.count > memoryLimit {
            let oldest = requestOrder.removeFirst()
            latestIdentityByRequest.removeValue(forKey: oldest)
        }
    }

    private func touchMemory(_ identity: String) {
        memoryOrder.removeAll { $0 == identity }
        memoryOrder.append(identity)
        while memoryOrder.count > memoryLimit {
            let oldest = memoryOrder.removeFirst()
            memory.removeValue(forKey: oldest)
        }
    }

    private func beginDiskWrite(_ image: SendableCGImage, identity: String, request: RequestKey) {
        guard let cacheDirectory else { return }
        let writeID = UUID()
        let task = Task.detached(priority: .utility) {
            Self.writeThumbnail(image, identity: identity, request: request, to: cacheDirectory)
            await self.finishDiskWrite(writeID)
        }
        pendingDiskWrites[writeID] = task
    }

    private func finishDiskWrite(_ writeID: UUID) {
        pendingDiskWrites.removeValue(forKey: writeID)
    }

    private func fileIdentity(for url: URL, maxDimension: Int) -> String? {
        ThumbnailFiles.identity(of: url).map { "v1|\($0)|\(maxDimension)" }
    }

    private func identityFromDiskIndex(for request: RequestKey) -> String? {
        guard let cacheDirectory else { return nil }
        let indexURL = cacheDirectory.appendingPathComponent(Self.indexName(for: request))
        return try? String(contentsOf: indexURL, encoding: .utf8)
    }

    private static func loadOrCreateThumbnail(
        at url: URL,
        identity: String,
        maxDimension: Int,
        cacheDirectory: URL?,
    ) -> WorkResult {
        if Task.isCancelled {
            return WorkResult(image: nil, decodedSource: false)
        }

        if let cachedURL = cacheDirectory?.appendingPathComponent(cacheName(for: identity)) {
            if let image = cachedImage(at: cachedURL) {
                return WorkResult(image: SendableCGImage(image), decodedSource: false)
            }
        }

        guard !Task.isCancelled,
              let source = MendedDNG.imageSource(for: url)
        else {
            return WorkResult(image: nil, decodedSource: false)
        }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return WorkResult(image: nil, decodedSource: false)
        }
        return WorkResult(image: SendableCGImage(image), decodedSource: true)
    }

    private static func cachedImage(at url: URL) -> CGImage? {
        ThumbnailFiles.read(url)
    }

    private static func writeThumbnail(
        _ image: SendableCGImage,
        identity: String,
        request: RequestKey,
        to directory: URL,
    ) {
        guard !Task.isCancelled else { return }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = ThumbnailFiles.jpegData(of: image.image), !Task.isCancelled else { return }

            let imageURL = directory.appendingPathComponent(cacheName(for: identity))
            try data.write(to: imageURL, options: .atomic)
            let indexURL = directory.appendingPathComponent(indexName(for: request))
            try identity.write(to: indexURL, atomically: true, encoding: .utf8)
        } catch {
            // A thumbnail remains useful in memory when the disk cache is unavailable.
        }
    }

    private static func cacheName(for identity: String) -> String {
        "\(stableHash(identity)).jpg"
    }

    private static func indexName(for request: RequestKey) -> String {
        "\(stableHash(request.value)).index"
    }

    private static func stableHash(_ value: String) -> String {
        ThumbnailFiles.stableHash(value)
    }
}
