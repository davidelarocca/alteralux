import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// Recipes, and the look of one photo given to others.
@MainActor
struct RecipeTests {
    /// A folder to add to the library, with four photos, and a place for the app's own files.
    /// The caller removes it.
    private struct Fixture {
        let root: URL
        let shoot: URL

        @MainActor
        init() throws {
            let pictures = try WindowedTests.writeTestPictures(count: 4)
            root = pictures[0].deletingLastPathComponent()
            shoot = root.appendingPathComponent("Shoot")
            try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
            for picture in pictures {
                try FileManager.default.moveItem(at: picture, to: shoot.appendingPathComponent(picture.lastPathComponent))
            }
        }

        /// A model as a launch of the app gives it, with an undo manager of its own.
        @MainActor
        func model() -> AppModel {
            let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: root.appendingPathComponent("support"))
            let undoManager = UndoManager()
            // No run loop groups the steps here: each change opens and closes its own.
            undoManager.groupsByEvent = false
            model.history.undoManager = undoManager
            return model
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A look that differs from a new photo's in its film, its exposure and its grain, on a
    /// photo with a white balance of its own.
    private func warmSlide() -> DevelopSettings {
        var settings = DevelopSettings()
        settings.filmID = "fujifilm_velvia_100"
        settings.scanFilm = true
        settings.exposureEV = 0.7
        settings.grainEnabled = false
        settings.temperature = 4200
        settings.tint = 12
        return settings
    }

    private func wait(_ what: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aRecipeIsSavedRenamedAndDeleted() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.addFolder(fixture.shoot)
        model.develop(model.library.photos[0])
        model.settings = warmSlide()

        // A name is needed, and the spaces around it are not part of it.
        await model.saveRecipe(named: "   ")
        #expect(model.recipes.isEmpty)
        await model.saveRecipe(named: " Warm slide ")
        await model.saveRecipe(named: "Another")
        #expect(model.recipes.map(\.name) == ["Another", "Warm slide"])
        let recipe = try #require(model.recipes.last)
        // The look, and not the light of the photo it was saved from.
        #expect(recipe.look.filmID == "fujifilm_velvia_100" && recipe.look.exposureEV == 0.7)
        #expect(recipe.look.temperature == nil && recipe.look.tint == nil)
        #expect(model.alertMessage == nil)

        // The next launch has the same recipes.
        let next = fixture.model()
        await next.loadRecipes()
        #expect(next.recipes == model.recipes)

        await next.rename(recipe, to: "Evening")
        #expect(next.recipes.map(\.name) == ["Another", "Evening"])
        #expect(next.recipes.last?.id == recipe.id)
        await next.rename(recipe, to: " ")
        #expect(next.recipes.map(\.name) == ["Another", "Evening"])

        await next.delete(recipe)
        #expect(next.recipes.map(\.name) == ["Another"])
    }

    @Test func aRecipeGivesItsLookAndOneUndoTakesItBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.addFolder(fixture.shoot)
        let photos = model.library.photos
        model.develop(photos[0])
        let recipe = Recipe(name: "Warm slide", from: warmSlide())

        // The photo has a white balance of its own, chosen before the recipe.
        model.settings.temperature = 6500
        model.settingsDidChange()
        model.settleChange()

        model.apply(recipe)
        #expect(model.settings.filmID == "fujifilm_velvia_100" && model.settings.scanFilm)
        #expect(model.settings.exposureEV == 0.7 && !model.settings.grainEnabled)
        #expect(model.settings.temperature == 6500 && model.settings.tint == nil)
        // It is kept at once, without waiting for the settings to stand still.
        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: photos[0]) == model.settings)

        model.undo()
        #expect(model.settings.filmID == DevelopSettings().filmID && model.settings.exposureEV == 0)
        #expect(model.settings.grainEnabled && model.settings.temperature == 6500)
        model.redo()
        #expect(model.settings.filmID == "fujifilm_velvia_100" && model.settings.exposureEV == 0.7)
        model.undo()
        model.undo()
        #expect(model.settings.temperature == nil)
        try await wait("nothing left to undo") { !model.canUndo }
    }

    @Test func aRecipeGoesToTheSelectionOfTheLibraryAndOneUndoTakesItBackFromAll() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.addFolder(fixture.shoot)
        let photos = model.library.photos
        let recipe = Recipe(name: "Warm slide", from: warmSlide())

        // One of the photos already has adjustments, with a white balance of its own.
        model.develop(photos[0])
        model.settings.temperature = 6500
        model.settings.halationAmount = 2
        model.settingsDidChange()
        model.showLibrary()
        let first = model.settings
        #expect(!model.canGiveLookToSelection)

        model.library.click(photos[0])
        model.library.click(photos[1], toggling: true)
        model.library.click(photos[2], toggling: true)
        #expect(model.canGiveLookToSelection)
        model.applyToSelection(recipe)

        // The photo on screen in the develop screen follows, and keeps its white balance.
        #expect(model.settings == recipe.applied(to: first) && model.settings.temperature == 6500)
        for photo in photos[0 ... 2] {
            #expect(model.history.kept(for: photo)?.filmID == "fujifilm_velvia_100")
        }
        #expect(model.history.kept(for: photos[1])?.temperature == nil)
        #expect(model.history.kept(for: photos[3]) == nil)
        try await wait("the marks of the grid") { model.library.adjusted == Set(photos[0 ... 2]) }

        model.undo()
        #expect(model.settings == first)
        #expect(model.history.kept(for: photos[0]) == first)
        // The photos that had no adjustments have none again.
        #expect(model.history.kept(for: photos[1]) == nil && model.history.kept(for: photos[2]) == nil)
        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: photos[0]) == first && model.history.kept(for: photos[1]) == nil)
        try await wait("the marks to go") { model.library.adjusted == [photos[0]] }

        model.redo()
        #expect(model.history.kept(for: photos[2])?.exposureEV == 0.7)
        #expect(model.settings.exposureEV == 0.7)
        // The next step back is the change made before the recipe.
        model.undo()
        model.undo()
        #expect(model.settings.halationAmount == 1 && model.settings.temperature == nil)

        // Discarded photos are taken back before they receive anything.
        model.library.click(photos[3])
        model.discardSelection()
        model.library.filter = .discarded
        model.library.click(photos[3])
        #expect(!model.canGiveLookToSelection)
    }

    @Test func adjustmentsAreCopiedFromOnePhotoAndPastedOnOthers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.addFolder(fixture.shoot)
        let photos = model.library.photos
        #expect(!model.canCopyAdjustments && !model.canPasteAdjustments)

        model.develop(photos[0])
        model.settings = warmSlide()
        #expect(model.canCopyAdjustments && !model.canPasteAdjustments)
        model.copyAdjustments()

        // On the photo on screen: the look arrives, the white balance stays.
        model.selectAdjacent(offset: 1)
        model.settings.tint = -8
        model.pasteAdjustments()
        #expect(model.settings.filmID == "fujifilm_velvia_100" && model.settings.exposureEV == 0.7)
        #expect(model.settings.temperature == nil && model.settings.tint == -8)
        model.undo()
        #expect(model.settings.filmID == DevelopSettings().filmID && model.settings.tint == -8)

        // On the selection of the library.
        model.showLibrary()
        #expect(!model.canPasteAdjustments)
        model.library.click(photos[2])
        model.library.click(photos[3], extending: true)
        #expect(!model.canCopyAdjustments && model.canPasteAdjustments)
        model.pasteAdjustments()
        #expect(model.history.kept(for: photos[2])?.filmID == "fujifilm_velvia_100")
        #expect(model.history.kept(for: photos[3])?.temperature == nil)

        // With one photo selected, its adjustments are the ones copied.
        model.library.click(photos[0])
        #expect(model.canCopyAdjustments)
        model.copiedAdjustments = nil
        model.copyAdjustments()
        #expect(model.copiedAdjustments == warmSlide())
    }
}

/// Exporting the selected photos of the library in one go.
@MainActor
struct BatchExportTests {
    @Test func theSelectionIsExportedBesideTheOriginalsEachWithItsOwnAdjustments() async throws {
        let pictures = try WindowedTests.writeTestPictures(count: 3)
        let folder = pictures[0].deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: folder.appendingPathComponent("support"))
        await model.start()
        await model.addFolder(folder)
        let photos = model.library.photos
        #expect(photos.count == 3)

        // One photo has a look of its own, one cannot be read any more.
        var slide = DevelopSettings()
        slide.filmID = "fujifilm_velvia_100"
        slide.scanFilm = true
        model.giveLook(slide, to: [photos[0]])
        await model.history.waitUntilSaved()
        try Data("not a photo".utf8).write(to: photos[2])
        model.exportOptions.longSide = 64

        for photo in photos {
            model.library.click(photo, toggling: true)
        }
        #expect(model.canPresentExport)
        model.presentExport()
        #expect(model.photosToExport == photos && model.isExportPresented)
        await model.exportPhotos()

        #expect(!model.isExporting && model.batchExport == nil && !model.isExportPresented)
        let developed = folder.appendingPathComponent(AppModel.developedFolderName)
        let written = try FileManager.default.contentsOfDirectory(atPath: developed.path).sorted()
        let film = { (id: String) in model.films.first { $0.id == id }?.displayName ?? "" }
        #expect(written == [
            "\(photos[0].deletingPathExtension().lastPathComponent) \(film("fujifilm_velvia_100")).jpg",
            "\(photos[1].deletingPathExtension().lastPathComponent) \(film(DevelopSettings().filmID)).jpg",
        ])
        // Only the photo that failed is named.
        let message = try #require(model.alertMessage)
        #expect(message.contains(photos[2].lastPathComponent) && !message.contains(photos[0].lastPathComponent))
    }

    @Test func aLongListOfFailedPhotosIsCountedPastTheFirstFew() {
        let names = (1 ... 11).map { "IMG_\($0).CR3" }
        let lines = AppModel.exportFailureMessage(for: names).split(separator: "\n")
        #expect(lines.count == 10)
        #expect(lines[0].contains("11") && lines[1] == "IMG_1.CR3" && lines[9].contains("3"))
        #expect(AppModel.exportFailureMessage(for: ["a.jpg"]).split(separator: "\n").count == 2)
    }
}

/// Exporting again photos that were exported before.
@MainActor
struct ExportAgainTests {
    @Test func anExportThatFindsFilesAlreadyThereAsksWhatToDo() async throws {
        let pictures = try WindowedTests.writeTestPictures(count: 2)
        let folder = pictures[0].deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: folder.appendingPathComponent("support"))
        await model.start()
        await model.addFolder(folder)
        let photos = model.library.photos
        model.exportOptions.longSide = 64
        let developed = folder.appendingPathComponent(AppModel.developedFolderName)
        let files = { try FileManager.default.contentsOfDirectory(atPath: developed.path).filter { !$0.hasPrefix(".") }.sorted() }

        // The first export has nothing to ask.
        await model.export([photos[0]], to: .subfolder(AppModel.developedFolderName))
        #expect(model.exportWaiting == nil)
        let first = try files()
        #expect(first.count == 1)
        let firstFile = developed.appendingPathComponent(first[0])
        let firstDate = try #require(try firstFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        // The second finds one file there: it writes nothing and waits.
        await model.export(photos, to: .subfolder(AppModel.developedFolderName))
        #expect(model.exportWaiting == WaitingExport(photos: photos, destination: .subfolder(AppModel.developedFolderName), existing: 1))
        #expect(try files() == first && !model.isExporting)

        // Skipping develops only the photo that was not there, and leaves the old file alone.
        await model.resumeExport(.skip)
        #expect(model.exportWaiting == nil && model.alertMessage == nil)
        #expect(try files().count == 2)
        let untouched = try URL(fileURLWithPath: firstFile.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(untouched == firstDate)

        // Replacing leaves as many files, with new ones in their place.
        try await Task.sleep(for: .milliseconds(1100))
        await model.export(photos, to: .subfolder(AppModel.developedFolderName))
        #expect(model.exportWaiting?.existing == 2)
        await model.resumeExport(.replace)
        #expect(try files().count == 2)
        let replaced = try #require(try URL(fileURLWithPath: firstFile.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        #expect(replaced > firstDate)

        // Keeping both writes the new files beside the old ones.
        await model.export(photos, to: .subfolder(AppModel.developedFolderName), existing: .keepBoth)
        #expect(try files().count == 4)

        // A photo developed with another film since is still one that was exported before.
        var slide = DevelopSettings()
        slide.filmID = "fujifilm_velvia_100"
        slide.scanFilm = true
        model.giveLook(slide, to: [photos[0]])
        await model.export([photos[0]], to: .subfolder(AppModel.developedFolderName))
        #expect(model.exportWaiting?.existing == 1)
        model.exportWaiting = nil

        // Leaving the question drops the export.
        await model.export(photos, to: .subfolder(AppModel.developedFolderName))
        model.exportWaiting = nil
        await model.resumeExport(.replace)
        #expect(try files().count == 4)
    }
}
