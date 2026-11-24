import AlteraluxKit
import AppKit
import Foundation
import Testing
@testable import AlteraluxUI

/// Photos handed over from outside the app to develop with a recipe: from the Finder's
/// "Develop with alteralux…" and from the Shortcuts action.
@MainActor
struct HandedOverTests {
    /// A recipe's fixture, the recipe writing small PNG files, and photos in a folder of their
    /// own, outside the library. The caller removes both folders.
    private struct Outside {
        let fixture: RecipeFilesTests.Fixture
        let recipe: Recipe
        let photos: [URL]

        @MainActor
        init(destination: RecipeFiles.Destination = .besideOriginals(folderName: "Out")) async throws {
            fixture = try await RecipeFilesTests.Fixture(photos: 1)
            var recipe = fixture.recipe
            recipe.files.options.longSide = 64
            recipe.files.options.format = .png
            recipe.files.destination = destination
            await fixture.model.save(recipe)
            self.recipe = try #require(fixture.model.recipes.first)
            photos = try WindowedTests.writeTestPictures(count: 2)
        }

        var folder: URL {
            photos[0].deletingLastPathComponent()
        }

        func remove() {
            fixture.remove()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// A pasteboard of its own holding `urls`, as the Finder sends them to a Services entry.
    private func pasteboard(with urls: [URL]) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("alteralux-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        return pasteboard
    }

    @Test func photosSentFromTheFinderAreDevelopedAtOnceBesideThemWithTheOnlyRecipe() async throws {
        let outside = try await Outside(destination: .sameFolder)
        defer { outside.remove() }
        let model = outside.fixture.model
        try await model.writableFolders.add(outside.folder)
        let note = outside.folder.appendingPathComponent("Notes.txt")
        try Data("not a photo".utf8).write(to: note)
        let libraryPhotos = model.library.photos
        let strip = model.photos.map(\.url)
        var windows = 0
        model.openMainWindow = { windows += 1 }
        model.askAboutFinderPhotos = { question in
            Issue.record("With one recipe that asks nothing, nothing is asked: \(question)")
            return .cancel
        }

        // Sent as the Finder sends them, with no window.
        let delegate = OpenFilesDelegate(model: model)
        let sent = pasteboard(with: outside.photos + [note])
        defer { sent.releaseGlobally() }
        var error: NSString?
        delegate.developWithWorkflow(sent, userData: nil, error: &error)
        await delegate.finderRequest?.value

        // No window, no question: the files are beside the photos, which stay out of the library.
        #expect(windows == 0 && !model.isExportPresented && model.alertMessage == nil && !model.isExporting)
        let velvia = try #require(model.films.first { $0.id == "fujifilm_velvia_100" }?.displayName)
        let written = try FileManager.default.contentsOfDirectory(atPath: outside.folder.path).filter { $0.contains(velvia) }
        #expect(written.sorted() == outside.photos.map { "\($0.deletingPathExtension().lastPathComponent) \(velvia).png" }.sorted())
        #expect(model.library.photos == libraryPhotos && model.photos.map(\.url) == strip)
    }

    @Test func withSeveralRecipesTheOneChosenInThePanelDevelops() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model
        try await model.writableFolders.add(outside.folder)
        var other = model.copy(of: outside.recipe)
        other.name = "Other"
        await model.save(other)
        var offered: [String] = []
        model.askAboutFinderPhotos = { question in
            if case let .run(photos, recipes, _) = question {
                offered = recipes.map(\.name)
                #expect(photos == 2 && recipes == model.recipes)
            }
            return .cancel
        }

        // Leaving the panel writes nothing.
        await model.developWithRecipe(handedOver: outside.photos)
        #expect(Set(offered) == ["Other", outside.recipe.name])
        #expect(!FileManager.default.fileExists(atPath: outside.folder.appendingPathComponent("Out").path))

        var shown: Recipe.ID?
        model.askAboutFinderPhotos = { question in
            if case let .run(_, _, chosen) = question {
                shown = chosen
            }
            return .run(outside.recipe)
        }
        await model.developWithRecipe(handedOver: outside.photos)
        let written = try FileManager.default.contentsOfDirectory(atPath: outside.folder.appendingPathComponent("Out").path)
        #expect(written.count == 2 && model.alertMessage == nil)

        // A second time, the panel shows the recipe chosen last, and the files already there
        // keep their names, with no question.
        await model.developWithRecipe(handedOver: outside.photos)
        #expect(shown == outside.recipe.id)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.folder.appendingPathComponent("Out").path).count == 4)
        #expect(model.exportWaiting == nil)
    }

    @Test func aRecipeThatLeavesSettingsOpenAsksOnlyThoseAndKeepsTheAnswers() async throws {
        let outside = try await Outside(destination: .sameFolder)
        defer { outside.remove() }
        let model = outside.fixture.model
        try await model.writableFolders.add(outside.folder)
        var asking = outside.recipe
        asking.files.asks = [.format]
        await model.save(asking)
        var asked: [FinderQuestion] = []
        model.askAboutFinderPhotos = { question in
            asked.append(question)
            guard case let .run(_, recipes, _) = question, var run = recipes.first else { return .cancel }
            run.files.options.format = .tiff
            return .run(run)
        }

        // One recipe, but it leaves the format open: the panel asks it.
        await model.developWithRecipe(handedOver: [outside.photos[0]])

        #expect(asked.count == 1 && model.alertMessage == nil)
        let written = try FileManager.default.contentsOfDirectory(atPath: outside.folder.path).filter { $0.hasSuffix(".tif") }
        #expect(written.count == 1)
        // The answer is offered next time; the recipe still asks.
        let kept = try #require(model.recipes.first)
        #expect(kept.files.options.format == .tiff && kept.files.asks == [.format])
        #expect(AppModel.summary(of: kept.files).hasSuffix(String(localized: "the rest asked each time")))
        #expect(!AppModel.settledSettings(of: kept.files).contains("TIFF"))
    }

    @Test func besideThePhotosAnOriginalIsNeverReplaced() async throws {
        let outside = try await Outside(destination: .sameFolder)
        defer { outside.remove() }
        let model = outside.fixture.model
        try await model.writableFolders.add(outside.folder)
        var recipe = outside.recipe
        recipe.files.naming = .name
        let original = try Data(contentsOf: outside.photos[0])

        // Named as the photo, in its folder, in its format: even Replace leaves the photo alone.
        await model.develop([outside.photos[0]], with: recipe, existing: .replace)

        #expect(try Data(contentsOf: outside.photos[0]) == original && model.alertMessage == nil)
        let name = outside.photos[0].deletingPathExtension().lastPathComponent
        #expect(FileManager.default.fileExists(atPath: outside.folder.appendingPathComponent("\(name) 2.png").path))
        #expect(model.exportWaiting == nil)
    }

    @Test func withNoRecipeThePanelLeadsToTheApp() async throws {
        let model = AppModel(
            dataDirectory: WindowedTests.engineData,
            editsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)"),
        )
        let photos = try WindowedTests.writeTestPictures(count: 2)
        defer { try? FileManager.default.removeItem(at: photos[0].deletingLastPathComponent()) }
        var windows = 0
        model.openMainWindow = { windows += 1 }
        var asked: FinderQuestion?
        model.askAboutFinderPhotos = { question in
            asked = question
            return .openApp
        }

        await model.developWithRecipe(handedOver: photos)

        #expect(asked == .noRecipe(photos: 2) && windows == 1)
    }

    @Test func onlyFilesThatAreNotPhotosSayWhy() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model
        let note = outside.folder.appendingPathComponent("Notes.txt")
        try Data("not a photo".utf8).write(to: note)

        var said: FinderQuestion?
        model.askAboutFinderPhotos = { question in
            said = question
            return .cancel
        }

        await model.developWithRecipe(handedOver: [note])

        // Said in the system's alert, not in the app's window.
        guard case .problem = said else {
            Issue.record("Nothing was said")
            return
        }
        #expect(!model.isExportPresented && model.alertMessage == nil)
    }

    @Test func aFolderOutsideTheLibraryIsAskedForOnce() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model

        // The library's own folders need nothing.
        #expect(await model.foldersNeedingPermission(for: model.library.photos).isEmpty)
        let needed = await model.foldersNeedingPermission(for: outside.photos)
        #expect(needed.map(\.lastPathComponent) == [outside.folder.lastPathComponent])

        // Once allowed, the folder and the ones inside it need nothing, at the next launch too.
        try await model.writableFolders.add(outside.folder)
        #expect(await model.foldersNeedingPermission(for: outside.photos).isEmpty)
        let next = AppModel(
            dataDirectory: WindowedTests.engineData,
            editsDirectory: outside.fixture.folder.appendingPathComponent("support"),
        )
        _ = await next.writableFolders.load()
        #expect(await next.foldersNeedingPermission(for: outside.photos).isEmpty)
    }

    @Test func aFolderHoldsOnlyWhatIsInsideIt() {
        let folder = URL(fileURLWithPath: "/Photos/Trip", isDirectory: true)
        #expect(AppModel.isInside(folder, folder))
        #expect(AppModel.isInside(URL(fileURLWithPath: "/Photos/Trip/Day 1"), folder))
        #expect(!AppModel.isInside(URL(fileURLWithPath: "/Photos/Trip 2"), folder))
        #expect(!AppModel.isInside(URL(fileURLWithPath: "/Photos"), folder))
    }

    @Test func aShortcutGetsTheFilesBack() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model
        let scratch = outside.folder.appendingPathComponent("Scratch")

        let files = try await model.developForShortcut(outside.photos, recipe: outside.recipe.id, scratch: scratch)

        #expect(files.count == 2 && files.allSatisfy { !$0.data.isEmpty && $0.type == .png })
        #expect(try Set(files.map(\.name)) == Set(FileManager.default.contentsOfDirectory(atPath: scratch.path)))
        // Nothing is written beside the photos: Shortcuts may have handed over copies.
        #expect(!FileManager.default.fileExists(atPath: outside.folder.appendingPathComponent("Out").path))

        // A run again keeps the earlier files and gives back only the new ones.
        let again = try await model.developForShortcut(outside.photos, recipe: outside.recipe.id, scratch: scratch)
        #expect(Set(again.map(\.name)).isDisjoint(with: files.map(\.name)))

        await #expect(throws: HandedOverError.recipeMissing) {
            try await model.developForShortcut(outside.photos, recipe: UUID(), scratch: scratch)
        }
    }

    @Test func aShortcutWithAFolderOfItsOwnLeavesTheFilesThere() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let outside = try await Outside(destination: .folder(FolderBookmark(for: output)))
        defer { outside.remove() }
        let model = outside.fixture.model
        let scratch = outside.folder.appendingPathComponent("Scratch")

        let files = try await model.developForShortcut(outside.photos, recipe: outside.recipe.id, scratch: scratch)

        #expect(try Set(files.map(\.name)) == Set(FileManager.default.contentsOfDirectory(atPath: output.path)))
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    @Test func shortcutsSeeTheRecipesByName() async throws {
        let outside = try await Outside()
        defer { outside.remove() }

        let choices = await outside.fixture.model.recipeChoices()

        #expect(choices.map(\.id) == [outside.recipe.id])
        #expect(choices.first?.name == outside.recipe.name && choices.first?.summary.contains("PNG") == true)
    }
}
