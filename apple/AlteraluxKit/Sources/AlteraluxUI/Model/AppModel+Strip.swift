import AlteraluxKit
import Foundation

// What the menu of a photo of the strip does. It acts on the photo it was opened on, which need
// not be the one on screen: the photo on screen stays where it is.

extension AppModel {
    /// Whether `item` is the photo on screen.
    func isOnScreen(_ item: PhotoItem) -> Bool {
        item.id == selectedID
    }

    // MARK: - Adjustments

    /// Copies the adjustments of a photo of the strip, to paste on others.
    func copyAdjustments(of item: PhotoItem) {
        // What is being changed on the photo on screen is part of its adjustments.
        closeChange()
        copiedAdjustments = item.settings
    }

    /// Gives the copied look to a photo of the strip. Like a recipe, it leaves the photo's
    /// white balance alone.
    func pasteAdjustments(on item: PhotoItem) {
        guard let copiedAdjustments else { return }
        if isOnScreen(item) {
            giveLook(copiedAdjustments)
        } else {
            giveLook(copiedAdjustments, to: [item.url])
        }
    }

    /// Whether a photo of the strip has adjustments to take away.
    func canResetAdjustments(of item: PhotoItem) -> Bool {
        isOnScreen(item) || item.hasAdjustments
    }

    /// Takes the adjustments of a photo of the strip away: the photo on screen keeps its film
    /// and paper, as its own Reset does; another one goes back to a photo never developed, as
    /// in the library. One undo gives them back.
    func resetAdjustments(of item: PhotoItem) {
        if isOnScreen(item) {
            closeChange()
            resetAdjustments()
            closeChange()
        } else if item.hasAdjustments {
            closeChange()
            set([PhotoAdjustments(photo: item.url, settings: DevelopSettings(), isKept: false)])
        }
    }

    /// Gives a recipe to a photo of the strip. One undo takes it back whole.
    func apply(_ recipe: Recipe, to item: PhotoItem) {
        if isOnScreen(item) {
            apply(recipe)
        } else {
            apply(recipe, to: [item.url])
        }
    }

    // MARK: - Export

    /// Whether a photo of the strip can be exported now.
    func canPresentExport(of item: PhotoItem) -> Bool {
        isOnScreen(item) ? canPresentExport : renderer != nil && !isExporting
    }

    /// Shows the export sheet for a photo of the strip: the photo on screen as its own Export
    /// does, another one developed with its own adjustments, as from the library.
    func presentExport(of item: PhotoItem) {
        guard canPresentExport(of: item) else { return }
        if isOnScreen(item) {
            presentExport()
        } else {
            photosToExport = [item.url]
            exportsWithRecipe = false
            isExportPresented = true
        }
    }

    // MARK: - Tags and discarding

    /// The Finder tags of a photo of the strip: as the library reads them, for a photo of the
    /// folder on screen, so they follow what the Finder does; the photo's own otherwise.
    func tags(of item: PhotoItem) -> [FinderTag] {
        library.infos[item.url]?.tags ?? item.tags
    }

    /// Reads again the Finder tags of the photos of the strip among `files`.
    func readTags(ofStripPhotosAmong files: [URL]) {
        let wanted = Set(files)
        let items = photos.filter { wanted.contains($0.url) }
        guard !items.isEmpty else { return }
        Task {
            let urls = items.map(\.url)
            let read = await Task.detached(priority: .utility) { urls.map(PhotoInfoReader.tags(of:)) }.value
            for (item, tags) in zip(items, read) {
                item.tags = tags
            }
        }
    }

    /// What Discard does to a photo of the strip, and so what its command is called.
    enum StripDiscard {
        /// The photo is marked and leaves the strip, as a discarded photo leaves the grid.
        case discard
        /// A discarded photo, in the strip because it was opened from the discarded ones, loses
        /// its mark and stays.
        case takeBack
        /// A photo that is not of the folder on screen has no grid to be hidden from: it only
        /// leaves the strip.
        case remove
    }

    /// What Discard does to `item`.
    func discardKind(of item: PhotoItem) -> StripDiscard {
        guard library.photos.contains(item.url) else { return .remove }
        return isDiscarded(item) ? .takeBack : .discard
    }

    /// Whether a photo of the strip is discarded.
    func isDiscarded(_ item: PhotoItem) -> Bool {
        library.discarded.contains(item.url)
    }

    /// Discards a photo of the strip, in the way `discardKind(of:)` says.
    func discard(_ item: PhotoItem) {
        switch discardKind(of: item) {
        case .discard: discardFromStrip(item)
        case .takeBack: setDiscarded(false, for: [item.url])
        case .remove: remove(item)
        }
    }

    /// Discards the photo on screen: the next one of the strip takes its place.
    func discardPhotoOnScreen() {
        if let selection {
            discard(selection)
        }
    }

    /// Marks a photo as discarded and takes it out of the strip. One undo takes the mark away
    /// and puts the photo back in its place.
    private func discardFromStrip(_ item: PhotoItem) {
        guard let index = photos.firstIndex(where: { $0.id == item.id }) else { return }
        let (url, wasOnScreen) = (item.url, isOnScreen(item))
        guard !library.setDiscarded(true, for: [url]).isEmpty else { return }
        remove(item)
        guard let undoManager = history.undoManager else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            model.takeBack(url, toStripAt: index, onScreen: wasOnScreen)
        }
        undoManager.endUndoGrouping()
    }

    /// Undoes a discard made from the strip; undone in its turn, the photo is discarded again.
    private func takeBack(_ url: URL, toStripAt index: Int, onScreen: Bool) {
        library.setDiscarded(false, for: [url])
        // The strip may hold another folder's photos by now: the photo then only loses its mark.
        let folder = url.deletingLastPathComponent()
        if photos.allSatisfy({ $0.url.deletingLastPathComponent() == folder }), let item = insert(url, at: index), onScreen {
            select(item)
        }
        guard let undoManager = history.undoManager else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            if let item = model.photos.first(where: { $0.url == url }) {
                model.discard(item)
            } else {
                model.setDiscarded(true, for: [url])
            }
        }
        undoManager.endUndoGrouping()
    }
}
