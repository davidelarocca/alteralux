import AlteraluxUI
import AppIntents
import Foundation

/// "Develop Photos" in Shortcuts: photos developed with a recipe of the app, and the files it
/// writes given back to the shortcut. It runs in the app, which starts without coming to the
/// front when it is not running.
struct DevelopPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "Develop Photos"
    static let description = IntentDescription(
        "Develops photos with a recipe of alteralux and gives back the files it writes. A recipe with a folder of its own also leaves them there.",
    )

    @Parameter(title: "Photos", supportedContentTypes: [.image])
    var photos: [IntentFile]

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Develop \(\.$photos) with \(\.$recipe)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let manager = FileManager.default
        // The copies of this run, removed at the end: the files go back to the shortcut as data.
        let run = manager.temporaryDirectory.appending(path: "Shortcuts/\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: run) }
        let copies = run.appending(path: "Photos", directoryHint: .isDirectory)
        try manager.createDirectory(at: copies, withIntermediateDirectories: true)

        // A photo that comes as a file on disk is developed there, with its own adjustments;
        // one that comes as data is developed from a copy.
        var reached: [URL] = []
        defer {
            for url in reached {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var urls: [URL] = []
        for photo in photos {
            if let url = photo.fileURL {
                if url.startAccessingSecurityScopedResource() {
                    reached.append(url)
                }
                if manager.isReadableFile(atPath: url.path) {
                    urls.append(url)
                    continue
                }
            }
            let copy = copies.appending(path: photo.filename.isEmpty ? UUID().uuidString : photo.filename)
            try photo.data.write(to: copy)
            urls.append(copy)
        }

        let files = try await model.developForShortcut(
            urls, recipe: recipe.id, scratch: run.appending(path: "Developed", directoryHint: .isDirectory),
        )
        return .result(value: files.map { IntentFile(data: $0.data, filename: $0.name, type: $0.type) })
    }
}

/// A recipe of the app as Shortcuts shows it: chosen by name, kept by id, so a recipe renamed
/// in the app stays chosen in the shortcut.
struct RecipeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"
    static let defaultQuery = RecipeQuery()

    let id: UUID
    let name: String
    /// What it writes: "JPEG · 2048 px · in “Developed” beside the originals".
    let summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }

    init(_ choice: RecipeChoice) {
        id = choice.id
        name = choice.name
        summary = choice.summary
    }
}

/// The recipes the app keeps, read when Shortcuts asks.
struct RecipeQuery: EntityQuery {
    @Dependency private var model: AppModel

    @MainActor
    func entities(for identifiers: [RecipeEntity.ID]) async throws -> [RecipeEntity] {
        await model.recipeChoices().filter { identifiers.contains($0.id) }.map(RecipeEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RecipeEntity] {
        await model.recipeChoices().map(RecipeEntity.init)
    }
}
