import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// The files a recipe writes: kept with it, and written when photos are developed with it.
@MainActor
struct RecipeFilesTests {
    /// A folder of test pictures in the library, a started model and a recipe saved from a look
    /// of its own. The caller removes `folder`.
    struct Fixture {
        let folder: URL
        let model: AppModel
        let recipe: Recipe

        @MainActor
        init(photos count: Int = 2, start: Bool = true) async throws {
            let pictures = try WindowedTests.writeTestPictures(count: count)
            folder = pictures[0].deletingLastPathComponent()
            model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: folder.appendingPathComponent("support"))
            if start {
                await model.start()
            }
            await model.addFolder(folder)
            model.develop(model.library.photos[0])
            var slide = DevelopSettings()
            slide.filmID = "fujifilm_velvia_100"
            slide.scanFilm = true
            model.settings = slide
            await model.save(model.newRecipe(named: "Slide"))
            recipe = try #require(model.recipes.first)
            // Back to a new photo's look, so the recipe's shows in the files it writes.
            model.settings = DevelopSettings()
            await model.history.waitUntilSaved()
        }

        func remove() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test func aRecipeKeepsTheFilesItWrites() async throws {
        let fixture = try await Fixture(start: false)
        defer { fixture.remove() }
        let model = fixture.model

        // A new recipe writes beside the photos, named after them and the film, and asks nothing.
        var recipe = fixture.recipe
        #expect(recipe.files == RecipeFiles() && recipe.files.destination == .sameFolder && recipe.files.naming == .nameAndFilm)
        recipe.name = " Web "
        recipe.files.options.longSide = 2048
        recipe.files.destination = .besideOriginals(folderName: " For the web ")
        await model.save(recipe)
        let kept = try #require(model.recipes.first)
        #expect(model.recipes.count == 1 && kept.id == recipe.id && kept.look == recipe.look)
        #expect(kept.name == "Web" && kept.files.destination == .besideOriginals(folderName: "For the web"))
        #expect(AppModel.summary(of: kept.files).contains("2048"))

        // The next launch has it.
        let next = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: fixture.folder.appendingPathComponent("support"))
        await next.loadRecipes()
        #expect(next.recipes == model.recipes)

        // A copy has the same look and files under a name that says so, and is another recipe.
        let copy = model.copy(of: kept)
        #expect(copy.id != kept.id && copy.look == kept.look && copy.files == kept.files && copy.filmModel == kept.filmModel)
        #expect(copy.name.contains("Web") && copy.name != kept.name)
        await model.save(copy)
        #expect(model.recipes.count == 2)

        // Deleting one leaves the other.
        await model.delete(kept)
        #expect(model.recipes.map(\.id) == [copy.id] && model.alertMessage == nil)
    }

    @Test func aRecipeNeedsANameAndAFolderNameItCanMake() {
        let recipe = Recipe(
            name: "Web", from: DevelopSettings(), files: RecipeFiles(destination: .besideOriginals(folderName: "Web")),
        )
        #expect(AppModel.canSave(recipe))
        var blank = recipe
        blank.name = "  "
        #expect(!AppModel.canSave(blank) && AppModel.canWrite(blank.files))
        for name in ["", " ", ".hidden", "a/b", "a:b"] {
            var bad = recipe
            bad.files.destination = .besideOriginals(folderName: name)
            #expect(!AppModel.canSave(bad), "\(name)")
            var badText = recipe
            badText.files.naming = .nameAndText(name)
            #expect(!AppModel.canSave(badText), "\(name)")
        }
        var text = recipe
        text.files.naming = .nameAndText("web")
        #expect(AppModel.canSave(text))
    }

    @Test func developingWithARecipeWritesItsFilesAndLeavesThePhotosAlone() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = fixture.model
        let photos = model.library.photos
        let before = photos.map { model.adjustments(of: $0).settings }

        var recipe = fixture.recipe
        recipe.files.options.longSide = 64
        recipe.files.options.format = .png
        recipe.files.destination = .besideOriginals(folderName: "Slides")
        await model.save(recipe)

        model.showLibrary()
        for photo in photos {
            model.library.click(photo, toggling: true)
        }
        #expect(model.canDevelopWithRecipe)
        model.presentRecipeRun()
        #expect(model.isExportPresented && model.exportsWithRecipe && model.photosToExport == photos)
        #expect(model.chosenRecipe?.id == recipe.id)
        await model.developWithRecipe()

        #expect(!model.isExporting && !model.isExportPresented && model.alertMessage == nil)
        let velvia = try #require(model.films.first { $0.id == "fujifilm_velvia_100" }?.displayName)
        let written = try FileManager.default.contentsOfDirectory(atPath: fixture.folder.appendingPathComponent("Slides").path)
        #expect(written.sorted() == photos.map { "\($0.deletingPathExtension().lastPathComponent) \(velvia).png" }.sorted())
        // Only files: the photos keep the adjustments they had.
        #expect(photos.map { model.adjustments(of: $0).settings } == before)

        // The plain export, opened afterwards, is not a recipe's.
        model.presentExport()
        #expect(!model.exportsWithRecipe)
        model.isExportPresented = false
    }

    @Test func aRecipeWritesIntoTheFolderItWasGiven() async throws {
        let fixture = try await Fixture(photos: 1)
        defer { fixture.remove() }
        let model = fixture.model
        let output = fixture.folder.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var recipe = fixture.recipe
        recipe.files.options.longSide = 64
        recipe.files.destination = try .folder(FolderBookmark(for: output))
        await model.save(recipe)
        #expect(try AppModel.summary(of: #require(model.recipes.first).files).contains("Chosen"))

        model.showLibrary()
        model.library.click(model.library.photos[0], toggling: true)
        model.presentRecipeRun(recipe)
        await model.developWithRecipe()
        #expect(model.alertMessage == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == 1)

        // A folder that is gone is named, and nothing is written.
        try FileManager.default.removeItem(at: output)
        model.presentRecipeRun(recipe)
        await model.developWithRecipe()
        #expect(model.alertMessage?.contains("Chosen") == true)
    }

    @Test func theWorkflowsKeptBeforeBecomeRecipesAtLaunch() async throws {
        let fixture = try await Fixture(start: false)
        defer { fixture.remove() }
        let support = fixture.folder.appendingPathComponent("support")
        // A workflow as the app kept it, beside the recipes: for the recipe, under another name.
        let workflows = URL(fileURLWithPath: support.path + "-library/workflows", isDirectory: true)
        try FileManager.default.createDirectory(at: workflows, withIntermediateDirectories: true)
        let id = UUID()
        let options = try #require(String(data: JSONEncoder().encode(ExportOptions(format: .png, longSide: 2048)), encoding: .utf8))
        let stored = """
        {"version":1,"workflow":{"id":"\(id.uuidString)","name":"Slides for the web","recipeID":"\(fixture.recipe.id.uuidString)",
        "adaptsToEachPhoto":true,"options":\(options),
        "naming":{"name":{}},"destination":{"besideOriginals":{"folderName":"Web"}},"asks":["size"]}}
        """
        try Data(stored.utf8).write(to: workflows.appendingPathComponent("\(id.uuidString).json"))

        let next = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: support)
        await next.loadRecipes()

        // Both are recipes now: the look as it was, and the way it was used, found by its id.
        #expect(next.recipes.map(\.name) == ["Slide", "Slides for the web"])
        let made = try #require(next.recipes.first { $0.id == id })
        #expect(made.look.filmID == "fujifilm_velvia_100" && made.look.autoExposure && made.look.autoWhiteBalance)
        #expect(made.files == RecipeFiles(
            options: ExportOptions(format: .png, longSide: 2048), naming: .name,
            destination: .besideOriginals(folderName: "Web"), asks: [.size],
        ))
        #expect(!FileManager.default.fileExists(atPath: workflows.path))
    }
}
