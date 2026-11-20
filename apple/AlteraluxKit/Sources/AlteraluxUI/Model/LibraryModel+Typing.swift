import Foundation

/// Typing a name in the grid goes to the photo it begins, as in the Finder.
extension LibraryModel {
    /// How long a pause in typing starts a new name.
    static let typingPause: TimeInterval = 1

    /// The first photo shown whose name begins with `prefix`, whatever its case and accents.
    func photo(namedLike prefix: String) -> URL? {
        guard !prefix.isEmpty else { return nil }
        return visiblePhotos.first { photo in
            photo.lastPathComponent.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
