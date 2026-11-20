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
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(store: EditStore) {
        self.store = store
    }

    /// The adjustments kept for the photo at `url`, if any.
    func kept(for url: URL) -> DevelopSettings? {
        store.load(for: url)
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
        item.keptSettings = settings
        saving = Task { [store, previous = saving, report] in
            await previous?.value
            do {
                try await store.save(settings, for: url)
            } catch {
                report(error)
            }
        }
    }

    /// Lets go of a photo that leaves the strip: its steps can no longer be undone.
    func forget(_ item: PhotoItem) {
        undoManager?.removeAllActions(withTarget: item)
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
    private func observe() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        refresh()
        guard let undoManager else { return }
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
            .NSUndoManagerCheckpoint,
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
