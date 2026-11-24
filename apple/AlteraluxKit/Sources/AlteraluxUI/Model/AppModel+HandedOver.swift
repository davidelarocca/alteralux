import AlteraluxKit
import AppKit
import Foundation
import UniformTypeIdentifiers

// Photos handed over from outside the app to develop with a recipe: from the Finder's
// "Develop with alteralux…" (a Services entry) and from the Shortcuts action "Develop Photos".
// They are developed as the library's selected photos are, and are not added to the library or
// to the strip.

extension AppModel {
    // MARK: - From the Finder

    /// Develops photos sent from the Finder with a recipe, out of sight: with the only one
    /// there is, at once, when it asks nothing; otherwise with the one chosen in a small panel
    /// at the center of the screen. The files are written without a question, and a file
    /// already there keeps its name. What is not a photo is left out.
    public func developWithRecipe(handedOver urls: [URL]) async {
        // The engine starts while the question, if any, is on screen.
        await loadRecipes()
        let engine = Task { await start() }
        let photos = urls.filter(Self.isPhoto)
        guard !photos.isEmpty else {
            return await tell(String(localized: "None of these files is a photo alteralux can develop."))
        }
        guard !isExporting else {
            return await tell(String(localized: "alteralux is already developing photos. Try again when it is done."))
        }
        guard let recipe = await recipeForFinder(photos: photos.count) else { return }
        if recipe.files.writesBesidePhotos {
            // The system's panel needs the app in front; it has no window of its own to show.
            NSApplication.shared.activate()
            guard await askToWrite(into: foldersNeedingPermission(for: photos)) else { return }
        }
        await engine.value
        await develop(photos, with: recipe, existing: .keepBoth)
        if let message = alertMessage {
            alertMessage = nil
            await tell(message)
        }
    }

    /// The recipe photos sent from the Finder are developed with: the only one, when it
    /// settles everything; otherwise the one chosen in the panel, with the answers to what it
    /// asks. `nil` when there is none to use.
    private func recipeForFinder(photos: Int) async -> Recipe? {
        if recipes.count == 1, recipes[0].files.asks.isEmpty {
            return recipes[0]
        }
        let question: FinderQuestion = recipes.isEmpty
            ? .noRecipe(photos: photos)
            : .run(photos: photos, recipes: recipes, chosen: exportRecipe)
        switch await askAboutFinderPhotos(question) {
        case let .run(recipe):
            await remember(recipe)
            return recipe
        case .openApp:
            showApp()
            return nil
        case .cancel:
            return nil
        }
    }

    /// Says what went wrong, in the system's alert, without the app's window.
    private func tell(_ message: String) async {
        _ = await askAboutFinderPhotos(.problem(message))
    }

    /// Shows the app: its Dock icon and its main window, in front.
    public func showApp() {
        openMainWindow?()
    }

    /// Whether `url` is a file of a kind the app develops.
    static func isPhoto(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return openableTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Folders to write into

    /// The folders that hold `photos` and that the app may not write into yet: outside the
    /// library's folders and the folders the user let it write into before. The sandbox lets
    /// the app read a photo handed over by the Finder, not write beside it.
    func foldersNeedingPermission(for photos: [URL]) async -> [URL] {
        let allowed = await library.roots.map(\.folder.url)
            + writableFolders.folders().filter(\.isAvailable).map(\.url)
        let holding = Set(photos.map { $0.deletingLastPathComponent().standardizedFileURL })
        return holding.filter { folder in !allowed.contains { Self.isInside(folder, $0) } }
            .sorted { $0.path < $1.path }
    }

    /// Whether `url` is `folder` or inside it.
    nonisolated static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return path.starts(with: base)
    }

    /// Asks the user, for each of `folders`, to let the app write into it: the system's open
    /// panel, on that folder. The folders allowed are remembered, so each is asked for once.
    /// Returns whether all of them were allowed.
    func askToWrite(into folders: [URL]) async -> Bool {
        for folder in folders {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            let name = folder.lastPathComponent
            panel.message = String(
                localized: "alteralux needs your permission to write in “\(name)”. Choosing a folder that holds it allows all inside, once and for all.",
            )
            panel.prompt = String(localized: "Allow")
            guard await panel.begin() == .OK, let chosen = panel.url else { return false }
            guard Self.isInside(folder, chosen) else {
                alertMessage = String(
                    localized: "“\(chosen.lastPathComponent)” does not hold the photos. Choose the folder “\(name)”, or one that holds it.",
                )
                return false
            }
            do {
                try await writableFolders.add(chosen)
            } catch {
                alertMessage = error.localizedDescription
                return false
            }
        }
        return true
    }

    // MARK: - From Shortcuts

    /// The recipes as the Shortcuts action offers them, by name.
    public func recipeChoices() async -> [RecipeChoice] {
        await loadRecipes()
        return recipes.map { RecipeChoice(id: $0.id, name: $0.name, summary: Self.summary(of: $0.files)) }
    }

    /// Develops `photos` with a recipe for the Shortcuts action, and gives back the files
    /// written. A recipe that writes into a folder of its own writes there; one that writes
    /// beside the originals writes into `scratch`, because what Shortcuts hands over is often a
    /// copy of the photo, and the shortcut takes the files on from there. A file already there
    /// is kept, and the new one takes the next free name.
    public func developForShortcut(_ photos: [URL], recipe id: UUID, scratch: URL) async throws -> [DevelopedFile] {
        await start()
        await loadRecipes()
        guard let renderer else { throw HandedOverError.engineUnavailable }
        guard let recipe = recipes.first(where: { $0.id == id }) else { throw HandedOverError.recipeMissing }
        let options = recipe.files.options
        let folder: URL
        switch recipe.files.destination {
        case .sameFolder, .besideOriginals:
            folder = scratch
        case let .folder(bookmark):
            guard let chosen = bookmark.resolve() else {
                throw HandedOverError.folderMissing(bookmark.name, recipe: recipe.name)
            }
            folder = chosen
        }
        let isScoped = folder.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jobs = exportJobs(photos.filter(Self.isPhoto), options: options, recipe: recipe)
        guard !jobs.isEmpty else { throw HandedOverError.noPhotos }
        let results = await BatchExporter(renderer: renderer, lenses: lenses)
            .export(jobs, to: .folder(folder), options: options, existing: .keepBoth)
        // Read while the folder can be reached: Shortcuts takes the files as data.
        let type = options.format.contentType
        let files = results.compactMap { result in
            result.destination.flatMap { url in
                (try? Data(contentsOf: url)).map { DevelopedFile(name: url.lastPathComponent, data: $0, type: type) }
            }
        }
        guard !files.isEmpty else {
            throw HandedOverError.nothingDeveloped(Self.exportFailureMessage(for: results.map(\.source.lastPathComponent)))
        }
        return files
    }
}

/// What the app asks about photos sent from the Finder, when the recipes do not say it alone.
public enum FinderQuestion: Equatable, Sendable {
    /// Which recipe, among several, and what the one chosen leaves open; `chosen` is the one
    /// shown first.
    case run(photos: Int, recipes: [Recipe], chosen: Recipe.ID?)
    /// Nothing to develop them with: there is no recipe yet.
    case noRecipe(photos: Int)
    /// Something that went wrong, to say.
    case problem(String)
}

/// The answer to a `FinderQuestion`.
public enum FinderAnswer: Equatable, Sendable {
    /// The recipe chosen, with the answers to what it asks.
    case run(Recipe)
    case openApp
    case cancel
}

/// A recipe as the Shortcuts action offers it.
public struct RecipeChoice: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    /// What it writes, in a line: "JPEG · 2048 px · in “Developed” beside the originals".
    public let summary: String
}

/// A file a recipe wrote, as the Shortcuts action gives it back.
public struct DevelopedFile: Sendable {
    public let name: String
    public let data: Data
    public let type: UTType
}

/// Why photos handed over to the app could not be developed.
public enum HandedOverError: LocalizedError, Equatable {
    case engineUnavailable
    case recipeMissing
    case folderMissing(String, recipe: String)
    case noPhotos
    case nothingDeveloped(String)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            String(localized: "alteralux could not start its film engine.")
        case .recipeMissing:
            String(localized: "The recipe is no longer in alteralux.")
        case let .folderMissing(folder, recipe):
            String(localized: "The folder “\(folder)” of the recipe “\(recipe)” cannot be found.")
        case .noPhotos:
            String(localized: "None of these files is a photo alteralux can develop.")
        case let .nothingDeveloped(message):
            message
        }
    }
}
