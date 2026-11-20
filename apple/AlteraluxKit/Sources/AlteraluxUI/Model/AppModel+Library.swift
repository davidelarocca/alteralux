import AlteraluxKit
import AppKit
import Foundation

// The library as the screens ask for it: adding folders, going from a folder to a photo and back.

/// A Finder tag to offer for the selected photos: its color, and how many of them carry it.
struct TagChoice: Equatable {
    let name: String
    let color: FinderTagColor?
    let carriedBy: Int
}

extension AppModel {
    /// Adds a folder the user chose to the library, and shows it.
    func addFolder(_ url: URL) async {
        do {
            try await library.add(url)
            showLibrary()
        } catch {
            alertMessage = String(localized: "“\(url.lastPathComponent)” could not be added to the library.")
        }
    }

    /// Asks which folder to add. The panel belongs to the library screen, so that is shown.
    func chooseFolder() {
        showsLibrary = true
        isFolderImporterPresented = true
    }

    /// Takes what was dropped on the window, chosen in a panel or opened from the Finder: photos
    /// are opened at once, folders are added to the library.
    func take(_ urls: [URL]) {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let files = urls.filter { !folders.contains($0) }
        if !files.isEmpty {
            open(files)
        }
        guard !folders.isEmpty else { return }
        Task {
            for folder in folders {
                await addFolder(folder)
            }
            // Photos that came with the folders are what the user asked to see.
            if !files.isEmpty {
                showsLibrary = false
            }
        }
    }

    /// Opens a photo of the folder on screen for developing, with the folder's photos in the
    /// strip, so previous and next walk the folder.
    func develop(_ photo: URL) {
        develop(photo, among: library.visiblePhotos)
    }

    /// Goes back to the library, keeping what was being changed.
    func showLibrary() {
        settleChange()
        showsLibrary = true
    }

    /// Whether there is a library to go back to.
    var hasLibrary: Bool {
        !library.isEmpty
    }

    // MARK: - Actions on the selection

    /// The selected photos, in the order of the grid.
    var selectedPhotos: [URL] {
        library.visiblePhotos.filter(library.selection.contains)
    }

    /// Discards the selected photos: they are marked and hidden, and stay on disk. Under the
    /// filter of the discarded photos it takes them back instead.
    func discardSelection() {
        let discarding = library.filter != .discarded
        let changed = library.setDiscarded(discarding, for: selectedPhotos)
        registerUndo(ofDiscarding: changed, wasDiscarded: !discarding)
    }

    /// Registers the way back from a discard, or from taking one back, as one step of undo.
    private func registerUndo(ofDiscarding photos: [URL], wasDiscarded: Bool) {
        guard let undoManager = history.undoManager, !photos.isEmpty else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            let changed = model.library.setDiscarded(wasDiscarded, for: photos)
            model.registerUndo(ofDiscarding: changed, wasDiscarded: !wasDiscarded)
        }
        undoManager.endUndoGrouping()
    }

    /// Moves the discarded photos of the folder on screen to the Trash.
    func emptyDiscarded() async {
        let failed = await library.emptyDiscarded().count { !$0.succeeded }
        if failed > 0 {
            alertMessage = String(localized: "\(failed) photos could not be moved to the Trash.")
        }
    }

    /// Moves the selected photos into a folder of the library.
    func moveSelection(to folder: URL) async {
        let results = await library.move(selectedPhotos, to: folder)
        let failed = results.count { !$0.succeeded }
        if failed > 0 {
            alertMessage = String(localized: "\(failed) photos could not be moved.")
        }
        registerUndo(ofMoving: results)
    }

    /// Registers the way back from a move: each photo returns to the folder it came from.
    private func registerUndo(ofMoving results: [FileActionResult]) {
        let moved = results.compactMap { result in
            result.destination.flatMap { $0 == result.source ? nil : (from: $0, to: result.source) }
        }
        guard let undoManager = history.undoManager, !moved.isEmpty else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            Task {
                var back: [FileActionResult] = []
                for photo in moved {
                    back += await model.library.move([photo.from], to: photo.to.deletingLastPathComponent())
                }
                model.registerUndo(ofMoving: back)
            }
        }
        undoManager.endUndoGrouping()
    }

    /// Copies the selected photos into a folder of the library.
    func copySelection(to folder: URL) async {
        let failed = await library.copy(selectedPhotos, to: folder).count { !$0.succeeded }
        if failed > 0 {
            alertMessage = String(localized: "\(failed) photos could not be copied.")
        }
    }

    /// The tags to offer for the selection: the Finder's own labels and the tags the selected
    /// photos already carry, each with the number of selected photos that have it.
    /// The Finder's labels come with their colors; a tag of the user's has the color the
    /// photos carry it with, if any.
    var tagChoices: [TagChoice] {
        let carried = library.tagsOfSelection()
        // The first of the Finder's labels is "none": not a tag to put on a photo.
        let labels = NSWorkspace.shared.fileLabels.enumerated().dropFirst().filter { !$0.element.isEmpty }
        var choices = labels.map { TagChoice(name: $0.element, color: FinderTagColor(rawValue: $0.offset), carriedBy: carried[$0.element] ?? 0) }
        // The tags the photos carry beyond the Finder's labels, with their color once the
        // folder has been read again.
        let colors = Dictionary(library.tagsInFolder.map { ($0.name, $0.color) }, uniquingKeysWith: { first, _ in first })
        for name in carried.keys.sorted() where !choices.contains(where: { $0.name == name }) {
            choices.append(TagChoice(name: name, color: colors[name].flatMap(\.self), carriedBy: carried[name] ?? 0))
        }
        return choices
    }

    /// Puts a tag on the selected photos, or takes it off when all of them have it.
    ///
    /// - Parameter color: the color a tag takes on the photos that did not have it.
    func toggleTag(_ tag: String, color: FinderTagColor? = nil) {
        let photos = selectedPhotos
        let carried = library.tagsOfSelection()[tag] ?? 0
        setTag(FinderTag(name: tag, color: color), isOn: carried < photos.count)
    }

    /// Puts a tag of the user's own on the selected photos: a name, and a color if they chose
    /// one. Whether `name` can be a tag: anything but blank.
    func addTag(named name: String, color: FinderTagColor?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setTag(FinderTag(name: name, color: color), isOn: true)
    }

    private func setTag(_ tag: FinderTag, isOn: Bool) {
        let failed = library.setTag(tag, isOn: isOn, for: selectedPhotos).count { !$0.succeeded }
        if failed > 0 {
            alertMessage = String(localized: "\(failed) photos could not be tagged.")
        }
    }

    /// Tells the library a photo's adjustments were kept, so its mark in the grid follows.
    func noteAdjustmentsInLibrary(of photo: URL) {
        Task { [history, library] in
            await history.waitUntilSaved()
            library.noteAdjustments(of: photo)
        }
    }
}
