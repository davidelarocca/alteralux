import AlteraluxKit
import Foundation

/// What the library does to the photos' files: moving, copying, duplicating, renaming and the
/// Trash, each followed by the folder read again.
extension LibraryModel {
    /// Moves the discarded photos of the folder on screen to the Trash, and returns what
    /// happened to each.
    func emptyDiscarded() async -> [FileActionResult] {
        let files = photos.filter(discarded.contains)
        let results = await Task.detached(priority: .userInitiated) { PhotoFileActions.trash(files) }.value
        await refresh()
        return results
    }

    /// Moves photos into a folder of the library.
    func move(_ files: [URL], to folder: URL) async -> [FileActionResult] {
        let results = await Task.detached(priority: .userInitiated) { PhotoFileActions.move(files, to: folder) }.value
        await refresh()
        return results
    }

    /// Copies photos into a folder of the library.
    func copy(_ files: [URL], to folder: URL) async -> [FileActionResult] {
        let results = await Task.detached(priority: .userInitiated) { PhotoFileActions.copy(files, to: folder) }.value
        await refresh()
        return results
    }

    /// The Finder tags of the selected photos, each with the number of them that carry it.
    func tagsOfSelection() -> [String: Int] {
        tags(of: Array(selection))
    }

    /// The Finder tags of some photos, each with the number of them that carry it.
    func tags(of chosen: [URL]) -> [String: Int] {
        PhotoFileActions.tags(ofAll: chosen)
    }

    /// Duplicates photos beside themselves, and selects the copies, as the Finder does.
    func duplicate(_ files: [URL], suffix: String) async -> [FileActionResult] {
        let results = await Task.detached(priority: .userInitiated) {
            PhotoFileActions.duplicate(files, suffix: suffix)
        }.value
        await refresh()
        selectPhotos(results.compactMap(\.destination))
        return results
    }

    /// Gives a photo a new name, its extension kept; the photo stays selected.
    func rename(_ file: URL, to name: String) async -> FileActionResult {
        let result = await Task.detached(priority: .userInitiated) { PhotoFileActions.rename(file, to: name) }.value
        await refresh()
        if let renamed = result.destination {
            selectPhotos([renamed])
        }
        return result
    }

    /// Moves photos to the Trash.
    func trash(_ files: [URL]) async -> [FileActionResult] {
        let results = await Task.detached(priority: .userInitiated) { PhotoFileActions.trash(files) }.value
        await refresh()
        return results
    }

    /// Makes these photos the selection, those of them the grid shows.
    private func selectPhotos(_ chosen: [URL]) {
        let files = Set(chosen.map(\.standardizedFileURL))
        selection = Set(visiblePhotos.filter { files.contains($0.standardizedFileURL) })
    }
}
