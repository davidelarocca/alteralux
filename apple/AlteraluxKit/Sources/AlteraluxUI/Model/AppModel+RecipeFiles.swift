import AlteraluxKit
import AppKit
import Foundation

// The files a recipe writes: developing photos with a recipe writes them as files of its format,
// size and name, where it says, from the library, the Finder and Shortcuts. It only writes files:
// the photos keep their own adjustments (ADR 0021).

extension AppModel {
    // MARK: - What a recipe can write

    /// Whether `files` say enough to be written: a folder to write to, and a text for the files'
    /// names when one is added.
    static func canWrite(_ files: RecipeFiles) -> Bool {
        if case let .nameAndText(text) = files.naming, !isFolderName(text) {
            return false
        }
        if case let .besideOriginals(folderName) = files.destination {
            return isFolderName(folderName)
        }
        return true
    }

    /// Whether `name` can name a folder beside the originals, or be added to a file's name: not
    /// blank, no slash or colon, and not hidden.
    static func isFolderName(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
    }

    // MARK: - Developing photos with a recipe

    /// Whether the selected photos of the library can be developed with a recipe.
    var canDevelopWithRecipe: Bool {
        showsLibrary && canGiveLookToSelection && renderer != nil && !isExporting && !recipes.isEmpty
    }

    /// Shows the export sheet for the selected photos of the library, to develop them with a
    /// recipe and write its files: `recipe`, or the one chosen last time.
    func presentRecipeRun(_ recipe: Recipe? = nil) {
        guard canDevelopWithRecipe else { return }
        photosToExport = selectedPhotos
        exportRecipe = (recipe ?? chosenRecipe ?? recipes.first)?.id
        exportsWithRecipe = true
        isExportPresented = true
    }

    /// The recipe chosen in the export sheet, if it is still there.
    var chosenRecipe: Recipe? {
        recipes.first { $0.id == exportRecipe }
    }

    /// Develops the photos the sheet was opened for with the recipe chosen in it: `run`, with
    /// the answers to what it asks, kept to be offered next time.
    func developWithRecipe(_ run: Recipe? = nil) async {
        guard let recipe = run ?? chosenRecipe else { return }
        await remember(recipe)
        await develop(photosToExport, with: recipe)
    }

    /// Keeps the answers a recipe was given to what it asks, to offer them next time, and
    /// remembers it as the one chosen last.
    func remember(_ run: Recipe) async {
        exportRecipe = run.id
        if let kept = recipes.first(where: { $0.id == run.id }), kept != run {
            await save(run)
        }
    }

    /// Develops `photos` with `recipe` and writes its files. Beside the photos, a folder the
    /// app may not write into yet is asked for first.
    ///
    /// - Parameter existing: what to do with the files of an earlier export; `nil` asks.
    func develop(_ photos: [URL], with recipe: Recipe, existing: ExistingFilePolicy? = nil) async {
        guard !photos.isEmpty else { return }
        let destination: ExportDestination
        switch recipe.files.destination {
        case .sameFolder, .besideOriginals:
            // Photos handed over may be in a folder the app cannot write into yet.
            let folders = await foldersNeedingPermission(for: photos)
            guard await askToWrite(into: folders) else { return }
            if case let .besideOriginals(folderName) = recipe.files.destination {
                destination = .subfolder(folderName)
            } else {
                destination = .sameFolder
            }
        case let .folder(bookmark):
            guard let folder = bookmark.resolve(), Self.isFolder(folder) else {
                alertMessage = String(
                    localized: "The folder “\(bookmark.name)” of the recipe “\(recipe.name)” cannot be found.",
                )
                return
            }
            destination = .folder(folder)
        }
        await export(photos, to: destination, options: recipe.files.options, recipe: recipe, existing: existing)
    }

    /// Whether there is a folder at `url`. A folder that was taken away is not made again.
    private static func isFolder(_ url: URL) -> Bool {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Describing what a recipe writes

    /// What a recipe writes, in a line: "JPEG · 2048 px · in “Developed” beside the photos",
    /// and whether it asks the rest each time.
    static func summary(of files: RecipeFiles) -> String {
        let settled = settledSettings(of: files)
        guard !files.asks.isEmpty else { return settled }
        let asked = String(localized: "the rest asked each time")
        return settled.isEmpty ? asked : "\(settled) · \(asked)"
    }

    /// What a recipe has settled of the files it writes, in a line, leaving out what it asks.
    static func settledSettings(of files: RecipeFiles) -> String {
        let format = switch files.options.format {
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .png: "PNG"
        }
        // A size in pixels is read as one number: "2048 px", not "2,048 px".
        let size = files.options.longSide.map { String(localized: "\(String($0)) px") }
            ?? String(localized: "Original size")
        let place = switch files.destination {
        case .sameFolder: String(localized: "beside the photos")
        case let .besideOriginals(folderName): String(localized: "in “\(folderName)” beside the photos")
        case let .folder(bookmark): String(localized: "in “\(bookmark.name)”")
        }
        return [
            files.asks.contains(.format) ? nil : format,
            files.asks.contains(.size) ? nil : size,
            files.asks.contains(.destination) ? nil : place,
        ].compactMap(\.self).joined(separator: " · ")
    }
}

extension AppModel {
    /// The system's panel for choosing a folder to write into, as Save As would: the folder
    /// chosen, remembered as a bookmark. `nil` when none is chosen.
    static func askForFolder() async throws -> FolderBookmark? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        // From the Finder's panel the app may be out of sight: the system's panel needs it in front.
        NSApplication.shared.activate()
        guard await panel.begin() == .OK, let folder = panel.url else { return nil }
        return try FolderBookmark(for: folder)
    }
}
