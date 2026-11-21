import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// Workflows: a recipe and the files it writes, kept beside the recipes and linked to them.
@MainActor
struct WorkflowTests {
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
            await model.saveRecipe(named: "Slide")
            recipe = try #require(model.recipes.first)
            // Back to a new photo's look, so the recipe's shows in what a workflow writes.
            model.settings = DevelopSettings()
            await model.history.waitUntilSaved()
        }

        func remove() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test func aWorkflowIsKeptAndFollowsItsRecipe() async throws {
        let fixture = try await Fixture(start: false)
        defer { fixture.remove() }
        let model = fixture.model

        var workflow = model.newWorkflow(for: fixture.recipe)
        #expect(workflow.name == "Slide" && workflow.recipeID == fixture.recipe.id)
        // A new workflow adapts, and writes beside the photos, named after them and the film.
        #expect(workflow.destination == .sameFolder && workflow.adaptsToEachPhoto && workflow.naming == .nameAndFilm)
        workflow.name = " Web "
        workflow.options.longSide = 2048
        workflow.destination = .besideOriginals(folderName: " For the web ")
        await model.save(workflow)
        let kept = try #require(model.workflows.first)
        #expect(kept.name == "Web" && kept.destination == .besideOriginals(folderName: "For the web"))
        #expect(model.summary(of: kept).contains("2048"))

        // The next launch has it.
        let next = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: fixture.folder.appendingPathComponent("support"))
        await next.loadRecipes()
        await next.loadWorkflows()
        #expect(next.workflows == model.workflows)

        // Renaming the recipe carries to the workflow, which names it by id.
        await model.rename(fixture.recipe, to: "Velvia")
        #expect(model.recipe(of: kept)?.name == "Velvia")
        #expect(try model.workflows(using: #require(model.recipes.first)) == [kept])

        // Deleting the recipe deletes its workflows; the others stay.
        await model.saveRecipe(named: "Other")
        let other = try #require(model.recipes.first { $0.name == "Other" })
        await model.save(model.newWorkflow(for: other))
        #expect(model.workflows.count == 2)
        try await model.delete(#require(model.recipes.first { $0.name == "Velvia" }))
        #expect(model.workflows.map(\.recipeID) == [other.id])
        #expect(model.alertMessage == nil)
    }

    @Test func aWorkflowNeedsANameAndAFolderNameItCanMake() {
        let workflow = Workflow(name: "Web", recipeID: UUID(), destination: .besideOriginals(folderName: "Web"))
        #expect(AppModel.canSave(workflow))
        var blank = workflow
        blank.name = "  "
        #expect(!AppModel.canSave(blank))
        for name in ["", " ", ".hidden", "a/b", "a:b"] {
            var bad = workflow
            bad.destination = .besideOriginals(folderName: name)
            #expect(!AppModel.canSave(bad), "\(name)")
            var badText = workflow
            badText.naming = .nameAndText(name)
            #expect(!AppModel.canSave(badText), "\(name)")
        }
        var text = workflow
        text.naming = .nameAndText("web")
        #expect(AppModel.canSave(text))
    }

    @Test func aWorkflowWritesFilesWithItsRecipeAndLeavesThePhotosAlone() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = fixture.model
        let photos = model.library.photos
        let before = photos.map { model.adjustments(of: $0).settings }

        var workflow = model.newWorkflow(for: fixture.recipe)
        workflow.options.longSide = 64
        workflow.options.format = .png
        workflow.destination = .besideOriginals(folderName: "Slides")
        await model.save(workflow)

        model.showLibrary()
        for photo in photos {
            model.library.click(photo, toggling: true)
        }
        #expect(model.canDevelopWithWorkflow)
        model.presentWorkflowRun()
        #expect(model.isExportPresented && model.exportsWithWorkflow && model.photosToExport == photos)
        #expect(model.chosenWorkflow?.id == workflow.id)
        await model.developWithWorkflow()

        #expect(!model.isExporting && !model.isExportPresented && model.alertMessage == nil)
        let velvia = try #require(model.films.first { $0.id == "fujifilm_velvia_100" }?.displayName)
        let written = try FileManager.default.contentsOfDirectory(atPath: fixture.folder.appendingPathComponent("Slides").path)
        #expect(written.sorted() == photos.map { "\($0.deletingPathExtension().lastPathComponent) \(velvia).png" }.sorted())
        // Only files: the photos keep the adjustments they had.
        #expect(photos.map { model.adjustments(of: $0).settings } == before)

        // The plain export, opened afterwards, is not a workflow's.
        model.presentExport()
        #expect(!model.exportsWithWorkflow)
        model.isExportPresented = false
    }

    @Test func aWorkflowWritesIntoTheFolderItWasGiven() async throws {
        let fixture = try await Fixture(photos: 1)
        defer { fixture.remove() }
        let model = fixture.model
        let output = fixture.folder.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var workflow = model.newWorkflow(for: fixture.recipe)
        workflow.options.longSide = 64
        workflow.destination = try .folder(FolderBookmark(for: output))
        await model.save(workflow)
        #expect(try model.summary(of: #require(model.workflows.first)).contains("Chosen"))

        model.showLibrary()
        model.library.click(model.library.photos[0], toggling: true)
        model.presentWorkflowRun(workflow)
        await model.developWithWorkflow()
        #expect(model.alertMessage == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == 1)

        // A folder that is gone is named, and nothing is written.
        try FileManager.default.removeItem(at: output)
        model.presentWorkflowRun(workflow)
        await model.developWithWorkflow()
        #expect(model.alertMessage?.contains("Chosen") == true)
    }
}
