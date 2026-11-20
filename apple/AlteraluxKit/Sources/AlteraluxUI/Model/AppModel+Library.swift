import Foundation

// The library as the screens ask for it: adding folders, going from a folder to a photo and back.

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

    /// Takes what was dropped on the window or chosen in a panel: folders go to the library,
    /// photos are opened.
    func take(_ urls: [URL]) async {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        for folder in folders {
            await addFolder(folder)
        }
        let files = urls.filter { !folders.contains($0) }
        if !files.isEmpty {
            open(files)
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

    /// Tells the library a photo's adjustments were kept, so its mark in the grid follows.
    func noteAdjustmentsInLibrary(of photo: URL) {
        Task { [history, library] in
            await history.waitUntilSaved()
            library.noteAdjustments(of: photo)
        }
    }
}
