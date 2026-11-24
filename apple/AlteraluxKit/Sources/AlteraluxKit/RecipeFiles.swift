import Foundation

/// The files a recipe writes when photos are developed with it, from the library, the Finder or
/// Shortcuts: their format, size and name, and where they go: the photos' own folder, a folder
/// beside them or one folder (ADR 0021).
///
/// Every recipe has them, ready from the start: files the size of the original, named after the
/// photo and the film, beside the photos.
public struct RecipeFiles: Codable, Sendable, Equatable {
    /// The format, color profile, quality, size and metadata of the files written.
    public var options: ExportOptions
    public var naming: Naming
    public var destination: Destination
    /// The settings left open: asked each time the recipe develops photos from the Finder or the
    /// library, with the values kept here chosen at first. The Shortcuts action uses the values
    /// kept.
    public var asks: Set<Setting>

    /// A setting a recipe can leave open, to be asked each time it develops photos.
    public enum Setting: String, Codable, Sendable, CaseIterable {
        case format
        case size
        case naming
        case destination
    }

    /// What the files written are called, from the photo's own name.
    public enum Naming: Codable, Sendable, Equatable {
        /// The photo's name and the film: "IMG_0042 Kodak Portra 400.jpg".
        case nameAndFilm
        /// The photo's name: "IMG_0042.jpg".
        case name
        /// The photo's name and a text of the user's: "IMG_0042 web.jpg".
        case nameAndText(String)
    }

    /// Where a recipe writes its files.
    public enum Destination: Codable, Sendable, Equatable {
        /// The folder each photo is in, beside it.
        case sameFolder
        /// A folder with this name inside the folder of each photo, created when it is not there.
        case besideOriginals(folderName: String)
        /// One folder the user chose.
        case folder(FolderBookmark)
    }

    /// Files named after the photo and the film, beside the photos, unless said otherwise.
    public init(
        options: ExportOptions = ExportOptions(), naming: Naming = .nameAndFilm, destination: Destination = .sameFolder,
        asks: Set<Setting> = [],
    ) {
        self.options = options
        self.naming = naming
        self.destination = destination
        self.asks = asks
    }

    /// Whether the files go beside the photos, in their folder or a folder inside it, and not
    /// into one folder chosen once.
    public var writesBesidePhotos: Bool {
        if case .folder = destination {
            false
        } else {
            true
        }
    }

    /// The name of the file written for a photo named `photoName` (without its extension),
    /// developed with `film`. Without the extension.
    public func fileName(photoName: String, film: String) -> String {
        switch naming {
        case .nameAndFilm: "\(photoName) \(film)"
        case .name: photoName
        case let .nameAndText(text): "\(photoName) \(text)"
        }
    }
}
