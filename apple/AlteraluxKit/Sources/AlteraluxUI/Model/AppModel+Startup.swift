import AlteraluxKit
import Foundation

// What the app reads at launch besides the engine: the recipes, the library and
// the folders the user let it write into.

extension AppModel {
    /// The most the thumbnails kept on disk take, in bytes: thousands of photos' worth.
    private nonisolated static let thumbnailCacheLimit: Int64 = 512 * 1024 * 1024

    /// Where the folders the user let the app write into are remembered: in the app's folders,
    /// or beside the library's own files for anything else (tests, previews).
    nonisolated static func writableFoldersStore(isApp: Bool, beside: URL) -> URL {
        isApp
            ? URL.applicationSupportDirectory.appending(path: "Library/writable-folders.plist")
            : beside.appending(path: "writable-folders.plist")
    }

    /// Reads the recipes and the library, and shows the library unless the app
    /// was started on a photo.
    func loadKeptState() async {
        await loadRecipes()
        await library.load()
        _ = await writableFolders.load()
        Task.detached(priority: .background) { [thumbnails = library.thumbnails] in
            thumbnails.pruneDiskCache(toAtMost: Self.thumbnailCacheLimit)
        }
        // The library is where the app opens, unless it was started on a photo.
        if photos.isEmpty, !library.isEmpty {
            showsLibrary = true
        }
    }
}
