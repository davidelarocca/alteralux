import Foundation

/// Keeps the recipes between launches, one file each, in a folder of the app's.
///
/// One file per recipe means saving, renaming or deleting one touches nothing else, and a file
/// that cannot be read costs only its own recipe.
public actor RecipeStore {
    /// The version of the stored format. A recipe written by a later version is left alone.
    static let formatVersion = 1

    private let directory: URL

    /// - Parameter directory: where the recipes are kept. Created when first needed.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The recipes that can be read, by name.
    public func all() -> [Recipe] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
        )) ?? []
        let recipes = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { file -> Recipe? in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return Self.decode(data)
            }
        // By name the way the Finder sorts ("Recipe 2" before "Recipe 10", case not splitting the
        // list), and by id when names are equal, so the order never changes between launches.
        return recipes.sorted { lhs, rhs in
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    /// Keeps a recipe: a new one, or in place of the one with the same id (a rename).
    public func save(_ recipe: Recipe) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(StoredRecipe(version: Self.formatVersion, recipe: recipe))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(for: recipe.id), options: .atomic)
    }

    /// Removes the recipe with this id. A recipe that is not there is not an error.
    public func delete(_ id: Recipe.ID) throws {
        let file = file(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    private func file(for id: Recipe.ID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private struct StoredRecipe: Codable {
        let version: Int
        let recipe: Recipe
    }

    /// The recipe `data` holds, if this version of the app can read it.
    private static func decode(_ data: Data) -> Recipe? {
        guard let stored = try? JSONDecoder().decode(StoredRecipe.self, from: data) else { return nil }
        return stored.version <= formatVersion ? stored.recipe : nil
    }
}
