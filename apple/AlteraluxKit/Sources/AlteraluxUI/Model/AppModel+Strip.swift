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

    /// Whether a photo of the strip can be discarded: discarding hides a photo in the library,
    /// so it is for the photos of the folder on screen.
    func canDiscard(_ item: PhotoItem) -> Bool {
        library.photos.contains(item.url)
    }

    /// Whether a photo of the strip is discarded.
    func isDiscarded(_ item: PhotoItem) -> Bool {
        library.discarded.contains(item.url)
    }

    /// Discards a photo of the strip, or takes it back. It stays in the strip, with its mark,
    /// until the folder is developed again.
    func toggleDiscarded(_ item: PhotoItem) {
        setDiscarded(!isDiscarded(item), for: [item.url])
    }
}
