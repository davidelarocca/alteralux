import CoreServices
import Foundation
import Synchronization

/// Watches a folder tree and coalesces filesystem events into change notifications.
public final class FolderWatcher: Sendable {
    private let stream: AsyncStream<Void>
    private let state: FolderWatcherState

    public var changes: AsyncStream<Void> {
        stream
    }

    public init(url: URL) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        self.stream = stream
        state = FolderWatcherState(url: url, continuation: continuation)
    }

    /// Stops the filesystem stream and finishes ``changes``.
    public func stop() {
        state.stop()
    }

    deinit {
        state.stop()
    }
}

private final class FolderWatcherState: Sendable {
    private struct Storage {
        // The mutex keeps the non-Sendable FSEvent handle owned until it is stopped and released.
        var eventStreamAddress: UInt?
        var changeGeneration: UInt64 = 0
        var isStopped = false
    }

    private let continuation: AsyncStream<Void>.Continuation
    private let debounceQueue = DispatchQueue(label: "alteralux.folder-watcher.debounce", qos: .utility)
    /// The queue the filesystem events arrive on. It is serial, and the stream is stopped on it:
    /// once `stop()` returns no event is being delivered, so the callback never reaches this
    /// object after it is gone.
    private let eventQueue = DispatchQueue(label: "alteralux.folder-watcher.events", qos: .utility)
    private let storage = Mutex(Storage())

    init(url: URL, continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
        startWatching(url)
    }

    deinit {
        stop()
    }

    func stop() {
        let eventStreamAddress = storage.withLock { state -> UInt? in
            guard !state.isStopped else { return nil }
            state.isStopped = true
            let eventStreamAddress = state.eventStreamAddress
            state.eventStreamAddress = nil
            return eventStreamAddress
        }

        if let eventStreamAddress {
            eventQueue.sync {
                guard let eventStream = FSEventStreamRef(bitPattern: eventStreamAddress) else { return }
                FSEventStreamStop(eventStream)
                FSEventStreamInvalidate(eventStream)
                FSEventStreamRelease(eventStream)
            }
        }
        continuation.finish()
    }

    func scheduleChange() {
        let generation = storage.withLock { state -> UInt64? in
            guard !state.isStopped else { return nil }
            state.changeGeneration += 1
            return state.changeGeneration
        }
        guard let generation else { return }
        debounceQueue.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            self?.emitChange(generation: generation)
        }
    }

    private func startWatching(_ url: URL) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil,
        )
        let paths = [url.path] as CFArray
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let state = Unmanaged<FolderWatcherState>.fromOpaque(info).takeUnretainedValue()
            state.scheduleChange()
        }

        guard let eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot),
        ) else {
            return
        }

        storage.withLock { $0.eventStreamAddress = UInt(bitPattern: eventStream) }
        FSEventStreamSetDispatchQueue(eventStream, eventQueue)
        if !FSEventStreamStart(eventStream) {
            storage.withLock { $0.eventStreamAddress = nil }
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
        }
    }

    private func emitChange(generation: UInt64) {
        let shouldEmit = storage.withLock { state -> Bool in
            !state.isStopped && state.changeGeneration == generation
        }
        if shouldEmit {
            continuation.yield(())
        }
    }
}
