import AlteraluxKit
import Foundation

/// The photos opened on their own, outside the library's folders (ADR 0026).
extension LibraryModel {
    /// Whether the photos on screen can be moved, duplicated and renamed: not those opened on
    /// their own, whose folder the sandbox does not give the app. The Trash takes them all.
    var arrangesFiles: Bool {
        place != .opened
    }

    /// Remembers photos the user opened, unless they are in a folder of the library: there
    /// they are found already.
    func noteOpened(_ urls: [URL]) async {
        let outside = urls.filter { !isInFolders($0) }
        guard !outside.isEmpty else { return }
        opened = await openedStore.add(outside)
        if place == .opened {
            await refresh()
        }
    }

    /// Forgets photos opened on their own. Nothing on disk changes. With none left, the grid
    /// shows a folder.
    func forgetOpened(_ urls: [URL]) async {
        opened = await openedStore.remove(urls)
        guard place == .opened else { return }
        if opened.isEmpty {
            await showFirstPlace()
        } else {
            await refresh()
        }
    }

    /// Whether a photo is in one of the folders the user added, or in a folder inside one.
    func isInFolders(_ photo: URL) -> Bool {
        let path = photo.standardizedFileURL.resolvingSymlinksInPath().path
        return roots.contains { root in
            let folder = root.folder.url.standardizedFileURL.resolvingSymlinksInPath().path
            return path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
        }
    }

    /// Forgets the photos opened on their own that a folder of the library now holds.
    func forgetOpenedInFolders() async {
        let inFolders = opened.filter(isInFolders)
        if !inFolders.isEmpty {
            opened = await openedStore.remove(inFolders)
        }
    }
}
