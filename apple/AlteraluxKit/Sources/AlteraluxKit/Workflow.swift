import Foundation

/// A way of using a recipe: the photos it is given to are developed with the recipe's look,
/// adapted to each photo or not, and written as files of a format, size and name, in the photos'
/// own folder, in a folder beside them or in one folder (ADR 0013, ADR 0014).
///
/// A workflow names its recipe by id, so renaming the recipe carries to it, and only writes
/// files: the photos it develops keep their own adjustments.
public struct Workflow: NamedItem, Equatable {
    public static let storageKey = "workflow"

    public let id: UUID
    public var name: String
    /// The recipe whose look the photos are developed with.
    public var recipeID: Recipe.ID
    /// Whether each photo starts from its own light: the exposure metered in it, and an
    /// automatic white balance where the white balance is the camera's.
    public var adaptsToEachPhoto: Bool
    /// The format, color profile, quality, size and metadata of the files written.
    public var options: ExportOptions
    public var naming: Naming
    public var destination: Destination
    /// The settings left open: asked each time the workflow runs from the Finder or the library,
    /// with the values kept here chosen at first. The Shortcuts action uses the values kept.
    public var asks: Set<Setting>

    /// A setting a workflow can leave open, to be asked each time it runs.
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

    /// Where a workflow writes its files.
    public enum Destination: Codable, Sendable, Equatable {
        /// The folder each photo is in, beside it.
        case sameFolder
        /// A folder with this name inside the folder of each photo, created when it is not there.
        case besideOriginals(folderName: String)
        /// One folder the user chose.
        case folder(FolderBookmark)
    }

    /// A new workflow adapts to each photo, names the files after the photo and the film, and
    /// writes them beside the photos.
    public init(
        id: UUID = UUID(), name: String, recipeID: Recipe.ID, adaptsToEachPhoto: Bool = true,
        options: ExportOptions = ExportOptions(), naming: Naming = .nameAndFilm, destination: Destination = .sameFolder,
        asks: Set<Setting> = [],
    ) {
        self.id = id
        self.name = name
        self.recipeID = recipeID
        self.adaptsToEachPhoto = adaptsToEachPhoto
        self.options = options
        self.naming = naming
        self.destination = destination
        self.asks = asks
    }

    /// Reads a saved workflow. One kept before workflows adapted, named their files and asked
    /// for settings did none of it: its files took the photo's name and the film.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            recipeID: values.decode(UUID.self, forKey: .recipeID),
            adaptsToEachPhoto: values.decodeIfPresent(Bool.self, forKey: .adaptsToEachPhoto) ?? false,
            options: values.decode(ExportOptions.self, forKey: .options),
            naming: values.decodeIfPresent(Naming.self, forKey: .naming) ?? .nameAndFilm,
            destination: values.decode(Destination.self, forKey: .destination),
            asks: values.decodeIfPresent(Set<Setting>.self, forKey: .asks) ?? [],
        )
    }

    /// The adjustments a photo with `settings` is developed with: the look of `recipe`, adapted
    /// to the photo when the workflow says so, on the photo's own white balance, lens
    /// correction and frame.
    public func settings(for settings: DevelopSettings, recipe: Recipe) -> DevelopSettings {
        recipe.applied(to: settings, adapting: adaptsToEachPhoto)
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
