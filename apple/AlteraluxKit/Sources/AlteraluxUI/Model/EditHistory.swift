import AlteraluxKit
import Foundation
import Observation

/// Remembers what is done to the photos: keeps each photo's adjustments so they are there the
/// next time it is opened, and registers each change so it can be undone.
///
/// A change is what happens between two moments of stillness: a whole drag of a slider, a film
/// chosen, a reset. It is one step of undo, and it is saved once, when the settings settle.
@MainActor
@Observable
final class EditHistory {
    /// Whether there is a step to undo, or to redo, in the window's undo manager.
    private(set) var canUndo = false
    private(set) var canRedo = false

    /// The undo manager of the window, where the Edit menu looks. Set by the main screen.
    @ObservationIgnored var undoManager: UndoManager? {
        didSet {
            if undoManager !== oldValue {
                observe()
            }
        }
    }

    /// Puts back the adjustments of a photo when a step is undone or redone.
    @ObservationIgnored var restore: (PhotoItem, DevelopSettings) -> Void = { _, _ in }
    /// Told when adjustments could not be kept anywhere.
    @ObservationIgnored var report: (any Error) -> Void = { _ in }

    @ObservationIgnored private let store: EditStore
    /// The photo whose adjustments are on screen, and how they were when they last stood still.
    @ObservationIgnored private weak var current: PhotoItem?
    @ObservationIgnored private var settled = DevelopSettings()
    @ObservationIgnored private var isChangeOpen = false
    /// The saves, one after the other, so the latest is the one that stays.
    @ObservationIgnored private var saving: Task<Void, Never>?
    /// What is on its way to the photos and not written yet, so a look at what a photo keeps
    /// does not have to wait for the disk. `settings` is `nil` for adjustments being forgotten.
    @ObservationIgnored private var pending: [URL: (settings: DevelopSettings?, write: Int)] = [:]
    @ObservationIgnored private var writes = 0
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(store: EditStore) {
        self.store = store
    }

    /// The adjustments kept for the photo at `url`, if any.
    func kept(for url: URL) -> DevelopSettings? {
        if let pending = pending[url] {
            return pending.settings
        }
        return store.load(for: url)
    }

    /// Keeps adjustments decided away from the develop screen, for photos that may not be in the
    /// strip: a recipe or a paste on a selection of the library, and their undo. `nil` forgets a
    /// photo's adjustments, as if it had never had any.
    func keep(_ changes: [(photo: URL, settings: DevelopSettings?)]) {
        guard !changes.isEmpty else { return }
        writes += 1
        let write = writes
        for change in changes {
            pending[change.photo] = (change.settings, write)
        }
        saving = Task { [store, previous = saving, report] in
            await previous?.value
            var failure: (any Error)?
            for change in changes {
                do {
                    if let settings = change.settings {
                        try await store.save(settings, for: change.photo)
                    } else {
                        try await store.remove(for: change.photo)
                    }
                } catch {
                    failure = failure ?? error
                }
                if pending[change.photo]?.write == write {
                    pending[change.photo] = nil
                }
            }
            // One message for the whole selection, not one per photo.
            if let failure {
                report(failure)
            }
        }
    }

    /// Starts following `item`: its adjustments as they are now are where a change starts from.
    func follow(_ item: PhotoItem?) {
        current = item
        settled = item?.settings ?? DevelopSettings()
        isChangeOpen = false
    }

    /// Called at every change of the adjustments of the photo on screen. The first one after a
    /// moment of stillness opens a step of undo, back to how they stood.
    func change(of item: PhotoItem) {
        guard item === current, !isChangeOpen, item.settings != settled else { return }
        isChangeOpen = true
        register(settled, for: item)
    }

    /// Called when the adjustments of `item` have stood still: closes the step and keeps them.
    func settle(_ item: PhotoItem) {
        if item === current {
            settled = item.settings
            isChangeOpen = false
        }
        guard item.settings != item.keptSettings else { return }
        let settings = item.settings
        let url = item.url
        let kept = item.keptSettings
        let hadAdjustments = item.hasAdjustments
        item.keptSettings = settings
        item.hasAdjustments = true
        writes += 1
        let write = writes
        pending[url] = (settings, write)
        saving = Task { [store, previous = saving, report] in
            await previous?.value
            defer {
                if pending[url]?.write == write {
                    pending[url] = nil
                }
            }
            do {
                try await store.save(settings, for: url)
            } catch {
                // Not kept after all: the next time the photo settles, it is tried again.
                if item.keptSettings == settings {
                    item.keptSettings = kept
                    item.hasAdjustments = hadAdjustments
                }
                report(error)
            }
        }
    }

    /// Lets go of a photo that leaves the strip: its steps can no longer be undone.
    func forget(_ item: PhotoItem) {
        undoManager?.removeAllActions(withTarget: item)
        // The undo manager posts nothing when steps are removed.
        refresh()
        if item === current {
            follow(nil)
        }
    }

    func undo() {
        undoManager?.undo()
    }

    func redo() {
        undoManager?.redo()
    }

    /// Waits until everything settled so far is written.
    func waitUntilSaved() async {
        await saving?.value
    }

    /// Registers the way back to `previous` for `item`, as one step.
    private func register(_ previous: DevelopSettings, for item: PhotoItem) {
        guard let undoManager else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: item) { [weak self] item in
            self?.revert(item, to: previous)
        }
        undoManager.endUndoGrouping()
    }

    /// Undoes or redoes a step: puts `settings` back on `item`, and registers the way back.
    private func revert(_ item: PhotoItem, to settings: DevelopSettings) {
        register(item.settings, for: item)
        if item === current {
            settled = settings
            isChangeOpen = false
        }
        restore(item, settings)
        settle(item)
    }

    /// Follows the undo manager, which says nothing to SwiftUI when its stacks change.
    ///
    /// Not its checkpoints: `canRedo` posts one each time it is read, so a refresh on every
    /// checkpoint asks for the next one, and the main thread never rests again after the first step.
    private func observe() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        refresh()
        guard let undoManager else { return }
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    private func refresh() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }
}
