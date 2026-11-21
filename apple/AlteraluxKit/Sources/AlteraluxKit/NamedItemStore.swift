import Foundation

/// Something the app keeps under a name of the user's, one file each: a recipe, a workflow.
public protocol NamedItem: Codable, Sendable, Identifiable where ID == UUID {
    var name: String { get }
    /// The key the item is written under in its file, beside the format's version ("recipe").
    static var storageKey: String { get }
}

/// The recipes, kept between launches one file each.
public typealias RecipeStore = NamedItemStore<Recipe>
/// The workflows, kept between launches one file each.
public typealias WorkflowStore = NamedItemStore<Workflow>

/// Keeps named items between launches, one file each, in a folder of the app's.
///
/// One file per item means saving, renaming or deleting one touches nothing else, and a file
/// that cannot be read costs only its own item.
public actor NamedItemStore<Item: NamedItem> {
    /// The version of the stored format. An item written by a later version is left alone.
    static var formatVersion: Int {
        1
    }

    private let directory: URL

    /// - Parameter directory: where the items are kept. Created when first needed.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The items that can be read, by name.
    public func all() -> [Item] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
        )) ?? []
        let items = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { file -> Item? in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return Self.decode(data)
            }
        // By name the way the Finder sorts ("Recipe 2" before "Recipe 10", case not splitting the
        // list), and by id when names are equal, so the order never changes between launches.
        return items.sorted { lhs, rhs in
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    /// Keeps an item: a new one, or in place of the one with the same id (a rename).
    public func save(_ item: Item) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Stored(version: Self.formatVersion, item: item))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(for: item.id), options: .atomic)
    }

    /// Removes the item with this id. An item that is not there is not an error.
    public func delete(_ id: Item.ID) throws {
        let file = file(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    private func file(for id: Item.ID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    /// A file's contents: `{"version": 1, "<storageKey>": {...}}`.
    private struct Stored: Codable {
        let version: Int
        let item: Item

        init(version: Int, item: Item) {
            self.version = version
            self.item = item
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: StorageKey.self)
            version = try values.decode(Int.self, forKey: StorageKey("version"))
            item = try values.decode(Item.self, forKey: StorageKey(Item.storageKey))
        }

        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: StorageKey.self)
            try values.encode(version, forKey: StorageKey("version"))
            try values.encode(item, forKey: StorageKey(Item.storageKey))
        }
    }

    /// The item `data` holds, if this version of the app can read it.
    private static func decode(_ data: Data) -> Item? {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return stored.version <= formatVersion ? stored.item : nil
    }
}

/// A key of a stored item's file, named by the item's type.
private struct StorageKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
