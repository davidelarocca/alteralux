import Foundation

/// A recipe and what to do with it: the photos it is given to are developed with its look and
/// written as files of a format and size, beside the originals or into one folder.
///
/// A workflow names its recipe by id, so renaming the recipe carries to it, and only writes
/// files: the photos it develops keep their own adjustments.
public struct Workflow: NamedItem, Equatable {
    public static let storageKey = "workflow"

    public let id: UUID
    public var name: String
    /// The recipe whose look the photos are developed with.
    public var recipeID: Recipe.ID
    /// The format, color profile, quality, size and metadata of the files written.
    public var options: ExportOptions
    public var destination: Destination

    /// Where a workflow writes its files.
    public enum Destination: Codable, Sendable, Equatable {
        /// A folder with this name beside each photo, created when it is not there.
        case besideOriginals(folderName: String)
        /// One folder the user chose.
        case folder(FolderBookmark)
    }

    public init(
        id: UUID = UUID(), name: String, recipeID: Recipe.ID, options: ExportOptions = ExportOptions(),
        destination: Destination,
    ) {
        self.id = id
        self.name = name
        self.recipeID = recipeID
        self.options = options
        self.destination = destination
    }

    /// The adjustments a photo with `settings` is developed with: the look of `recipe`, given
    /// as a recipe gives it, on the photo's own white balance, lens correction and frame.
    public func settings(for settings: DevelopSettings, recipe: Recipe) -> DevelopSettings {
        recipe.applied(to: settings)
    }
}
