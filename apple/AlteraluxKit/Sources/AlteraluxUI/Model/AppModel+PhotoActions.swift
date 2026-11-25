import AlteraluxKit
import Foundation

// The rest of what a photo's menu in the library does: duplicating, renaming and trashing the
// files, turning the photos and taking their adjustments away.

extension AppModel {
    // MARK: - Files

    /// Duplicates the selected photos beside themselves, with their adjustments and tags, and
    /// selects the copies.
    func duplicateSelection() async {
        let suffix = String(localized: "copy", comment: "Put after the name of a duplicated photo: “IMG_0042 copy.jpg”")
        let failed = await library.duplicate(selectedPhotos, suffix: suffix).count { !$0.succeeded }
        if failed > 0 {
            alertMessage = String(localized: "\(failed) photos could not be duplicated.")
        }
    }

    /// Whether `name` can be a photo's new name, its extension left out.
    static func isPhotoName(_ name: String) -> Bool {
        PhotoFileActions.isFileName(name)
    }

    /// Gives a photo a new name, its extension kept. One undo gives it back its name.
    func rename(_ photo: URL, to name: String) async {
        let result = await library.rename(photo, to: name)
        if let error = result.error {
            alertMessage = String(localized: "“\(photo.lastPathComponent)” could not be renamed. \(error)")
            return
        }
        guard let renamed = result.destination, renamed != photo, let undoManager = history.undoManager else { return }
        let name = photo.deletingPathExtension().lastPathComponent
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            Task { await model.rename(renamed, to: name) }
        }
        undoManager.endUndoGrouping()
    }

    /// Moves the selected photos to the Trash, where the Finder can put them back.
    func trashSelection() async {
        await trash(selectedPhotos)
    }

    /// Moves photos to the Trash, where the Finder can put them back. Those in the strip leave
    /// it: what was changed on them is kept with the files first, so a photo put back comes
    /// back as it was left.
    func trash(_ files: [URL]) async {
        closeChange()
        await history.waitUntilSaved()
        let results = await library.trash(files)
        let gone = Set(results.filter(\.succeeded).map(\.source))
        for item in photos where gone.contains(item.url) {
            remove(item)
        }
        let failed = results.count - gone.count
        if failed > 0 {
            alertMessage = String(localized: "\(failed) photos could not be moved to the Trash.")
        }
    }

    // MARK: - Adjustments

    /// Turns the selected photos a quarter, as the crop does: their thumbnails turn too. One
    /// undo turns them back.
    func turnSelection(clockwise: Bool) {
        closeChange()
        set(selectedPhotos.map { photo in
            var settings = adjustments(of: photo).settings
            let crop = settings.crop ?? PhotoCrop(left: 0, top: 0, width: 1, height: 1)
            settings.crop = clockwise ? crop.turnedRight() : crop.turnedLeft()
            return PhotoAdjustments(photo: photo, settings: settings, isKept: true)
        })
    }

    /// Takes every adjustment away from the selected photos, as if they had never been
    /// developed. One undo gives them back.
    func resetAdjustmentsOfSelection() {
        closeChange()
        set(selectedPhotos.filter(library.adjusted.contains).map { photo in
            PhotoAdjustments(photo: photo, settings: DevelopSettings(), isKept: false)
        })
    }
}
