import Foundation
import Testing
@testable import AlteraluxKit

/// Keeping recipes between launches, one file each.
struct RecipeStoreTests {
    /// A temporary folder for one test and a store that keeps its recipes in a folder inside it.
    private struct Fixture {
        let folder: URL
        let directory: URL
        let store: RecipeStore

        init() {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
            directory = folder.appendingPathComponent("nested").appendingPathComponent("recipes")
            store = RecipeStore(directory: directory)
        }

        func file(for recipe: Recipe) -> URL {
            directory.appendingPathComponent("\(recipe.id.uuidString).json")
        }

        func remove() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func look(_ exposure: Double = 0.7) -> DevelopSettings {
        var settings = DevelopSettings()
        settings.filmID = "fujifilm_velvia_100"
        settings.exposureEV = exposure
        return settings
    }

    @Test func aSavedRecipeIsReadBack() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let recipe = Recipe(name: "Velvia", from: look())
        try await fixture.store.save(recipe)
        #expect(await fixture.store.all() == [recipe])
        // A new store over the same folder, as after a launch.
        #expect(await RecipeStore(directory: fixture.directory).all() == [recipe])
        #expect(FileManager.default.fileExists(atPath: fixture.file(for: recipe).path))
    }

    @Test func noFolderYetMeansNoRecipes() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        #expect(await fixture.store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test func recipesComeByNameTheWayTheFinderSortsThem() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        for name in ["Recipe 10", "recipe 2", "Banana", "apple"] {
            try await fixture.store.save(Recipe(name: name, from: look()))
        }
        #expect(await fixture.store.all().map(\.name) == ["apple", "Banana", "recipe 2", "Recipe 10"])
    }

    @Test func twoRecipesMayShareANameAndKeepAStableOrder() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let recipes = (0 ..< 4).map { _ in Recipe(name: "Same", from: look()) }
        for recipe in recipes {
            try await fixture.store.save(recipe)
        }
        let expected = recipes.sorted { $0.id.uuidString < $1.id.uuidString }
        #expect(await fixture.store.all() == expected)
    }

    @Test func aRenameReplacesTheFileAndKeepsOneRecipe() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        var recipe = Recipe(name: "Before", from: look())
        let other = Recipe(name: "Other", from: look(-1))
        try await fixture.store.save(recipe)
        try await fixture.store.save(other)
        recipe.name = "After"
        try await fixture.store.save(recipe)

        #expect(await fixture.store.all() == [recipe, other])
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
        #expect(files.count == 2)
    }

    /// A recipe says which film model its look was made with, and keeps saying it when it is
    /// renamed by an app built with a later engine; one saved before says nothing.
    @Test func aRecipeKeepsTheFilmModelItWasMadeWith() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        #expect(Recipe(name: "Now", from: look()).filmModel == FilmModel.version)

        var recipe = Recipe(name: "Before", from: look(), filmModel: "0.0.1")
        try await fixture.store.save(recipe)
        recipe = try #require(await fixture.store.all().first)
        recipe.name = "After"
        try await fixture.store.save(recipe)
        let renamed = try #require(await fixture.store.all().first)
        #expect(renamed.name == "After" && renamed.filmModel == "0.0.1")

        // A recipe saved before the app wrote the model down.
        let written = try String(contentsOf: fixture.file(for: recipe), encoding: .utf8)
        let before = written.replacingOccurrences(of: #""filmModel":"0.0.1","#, with: "")
        #expect(before != written)
        try Data(before.utf8).write(to: fixture.file(for: recipe))
        let earlier = try #require(await fixture.store.all().first)
        #expect(earlier.filmModel == nil && earlier.look == recipe.look)
    }

    @Test func deletingRemovesOnlyThatRecipe() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let first = Recipe(name: "First", from: look())
        let second = Recipe(name: "Second", from: look())
        try await fixture.store.save(first)
        try await fixture.store.save(second)

        try await fixture.store.delete(first.id)
        #expect(await fixture.store.all() == [second])
        // One that is not there is not an error.
        try await fixture.store.delete(first.id)
        try await RecipeStore(directory: fixture.folder.appendingPathComponent("never")).delete(UUID())
    }

    @Test func aFileThatCannotBeReadOrIsFromALaterVersionIsLeftOutAndLeftOnDisk() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let kept = Recipe(name: "Kept", from: look())
        try await fixture.store.save(kept)

        let junk = fixture.directory.appendingPathComponent("junk.json")
        try Data("not json".utf8).write(to: junk)
        let later = fixture.directory.appendingPathComponent("\(UUID().uuidString).json")
        let laterData = Data(
            #"{"version":99,"recipe":{"id":"\#(UUID().uuidString)","name":"Future","look":{}}}"#.utf8,
        )
        try laterData.write(to: later)
        let note = fixture.directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: note)

        #expect(await fixture.store.all() == [kept])
        #expect(try Data(contentsOf: junk) == Data("not json".utf8))
        #expect(try Data(contentsOf: later) == laterData)
        #expect(try Data(contentsOf: note) == Data("hello".utf8))
    }

    @Test func aRecipeNeverCarriesAWhiteBalance() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        var settings = look()
        settings.temperature = 4200
        settings.tint = 12
        let recipe = Recipe(name: "Warm", from: settings)
        try await fixture.store.save(recipe)

        let read = try #require(await fixture.store.all().first)
        #expect(read.look.temperature == nil)
        #expect(read.look.tint == nil)
        #expect(read == recipe)

        // A file written by hand with a white balance in it is read without it.
        var handWritten = try String(contentsOf: fixture.file(for: recipe), encoding: .utf8)
        handWritten = handWritten.replacingOccurrences(of: #""exposureEV""#, with: #""temperature":3000,"exposureEV""#)
        try Data(handWritten.utf8).write(to: fixture.file(for: recipe))
        let reread = try #require(await fixture.store.all().first)
        #expect(reread.look.temperature == nil)
    }

    @Test func aRecipeSavedBeforeRecipesWroteFilesIsReadWithItsLookAndANewRecipesFiles() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let recipe = Recipe(name: "Portra di sera", from: DevelopSettings(filmID: "kodak_portra_400"))
        try await fixture.store.save(recipe)
        // Recipes once kept whether they adapted to each photo, and had no files of their own.
        let file = fixture.file(for: recipe)
        var stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var item = try #require(stored["recipe"] as? [String: Any])
        #expect(item["files"] != nil)
        item["files"] = nil
        item["adaptsToEachPhoto"] = true
        stored["recipe"] = item
        try JSONSerialization.data(withJSONObject: stored).write(to: file)
        let read = try #require(await fixture.store.all().first)
        #expect(read == recipe && read.files == RecipeFiles())
    }

    @Test func aRecipeStartsEachPhotoFromItsLightWhenItWasSavedOnAutomatic() {
        // Saved with both on Automatic: the exposure is metered and the white balance measured.
        var look = DevelopSettings(filmID: "kodak_ektar_100")
        look.autoWhiteBalance = true
        look.temperature = 5200
        let automatic = Recipe(name: "Ektar", from: look)
        #expect(automatic.look.autoExposure && automatic.look.autoWhiteBalance && automatic.look.temperature == nil)
        let given = automatic.applied(to: DevelopSettings())
        #expect(given.filmID == "kodak_ektar_100" && given.autoExposure && given.autoWhiteBalance)

        // A white balance chosen by hand stays.
        let chosen = DevelopSettings(temperature: 3200, tint: 4)
        let kept = automatic.applied(to: chosen)
        #expect(kept.temperature == 3200 && kept.tint == 4 && !kept.autoWhiteBalance)

        // Saved with both by hand: one exposure for every photo, and each photo's own white balance.
        look.autoExposure = false
        look.exposureEV = 0.7
        look.autoWhiteBalance = false
        let fixed = Recipe(name: "Ektar by hand", from: look)
        let plain = fixed.applied(to: DevelopSettings())
        #expect(!plain.autoExposure && plain.exposureEV == 0.7 && !plain.autoWhiteBalance)
        // A photo already on the automatic white balance keeps it.
        #expect(fixed.applied(to: DevelopSettings(autoWhiteBalance: true)).autoWhiteBalance)
    }

    @Test func aRecipeLeavesThePhotosLensCorrection() {
        let recipe = Recipe(name: "Senza correzione", from: DevelopSettings(lensCorrection: false))
        #expect(recipe.applied(to: DevelopSettings()).lensCorrection == true)
        #expect(recipe.applied(to: DevelopSettings(lensCorrection: nil)).lensCorrection == nil)
    }
}

/// The files a recipe writes, kept with it, and the workflows kept before recipes had them.
struct RecipeFilesStoreTests {
    @Test func aRecipeNamesItsFilesAsItSays() {
        var files = RecipeFiles()
        #expect(files.fileName(photoName: "IMG_0042", film: "Kodak Portra 400") == "IMG_0042 Kodak Portra 400")
        files.naming = .name
        #expect(files.fileName(photoName: "IMG_0042", film: "Kodak Portra 400") == "IMG_0042")
        files.naming = .nameAndText("web")
        #expect(files.fileName(photoName: "IMG_0042", film: "Kodak Portra 400") == "IMG_0042 web")
        #expect(files.destination == .sameFolder && files.writesBesidePhotos && files.asks.isEmpty)
    }

    @Test func aRecipesFilesAreReadBack() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("Output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = RecipeStore(directory: folder.appendingPathComponent("recipes"))
        let beside = Recipe(
            name: "Web", from: DevelopSettings(),
            files: RecipeFiles(naming: .nameAndText("web"), destination: .besideOriginals(folderName: "Web"), asks: [.size]),
        )
        let chosen = try Recipe(
            name: "Print", from: DevelopSettings(),
            files: RecipeFiles(options: ExportOptions(format: .tiff, longSide: 4096), destination: .folder(FolderBookmark(for: output))),
        )
        try await store.save(beside)
        try await store.save(chosen)
        #expect(await RecipeStore(directory: folder.appendingPathComponent("recipes")).all() == [chosen, beside])

        // The bookmark finds the folder again.
        #expect(!chosen.files.writesBesidePhotos)
        if case let .folder(bookmark) = chosen.files.destination {
            #expect(bookmark.resolve()?.standardizedFileURL.path == output.standardizedFileURL.path)
            #expect(bookmark.name == "Output")
        }
    }

    /// Writes a workflow as the app kept it before recipes wrote files.
    private func writeWorkflow(
        _ id: UUID = UUID(), named name: String, recipe: Recipe, adapts: Bool?, in directory: URL,
    ) throws {
        var workflow: [String: Any] = try [
            "id": id.uuidString, "name": name, "recipeID": recipe.id.uuidString,
            "options": JSONSerialization.jsonObject(with: JSONEncoder().encode(ExportOptions(format: .tiff))),
            "destination": ["besideOriginals": ["folderName": "Prints"]],
        ]
        if let adapts {
            workflow["adaptsToEachPhoto"] = adapts
            workflow["naming"] = ["nameAndText": ["_0": "print"]]
            workflow["asks"] = ["destination"]
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "workflow": workflow])
            .write(to: directory.appendingPathComponent("\(id.uuidString).json"))
    }

    @Test func workflowsBecomeRecipesWithTheirFilesAndTheirIds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecipeStore(directory: folder.appendingPathComponent("recipes"))
        let workflows = folder.appendingPathComponent("workflows")
        var look = DevelopSettings(filmID: "kodak_ektar_100")
        look.autoExposure = false
        let ektar = Recipe(name: "Ektar", from: look, filmModel: "0.0.1")
        let untouched = Recipe(name: "Untouched", from: DevelopSettings())
        try await store.save(ektar)
        try await store.save(untouched)
        // One with the recipe's name, which adapted; one under a name of its own, from before
        // workflows adapted and named their files; one whose recipe is gone.
        let same = UUID()
        let web = UUID()
        try writeWorkflow(same, named: "Ektar", recipe: ektar, adapts: true, in: workflows)
        try writeWorkflow(web, named: "Ektar for print", recipe: ektar, adapts: nil, in: workflows)
        try writeWorkflow(named: "Orphan", recipe: Recipe(name: "Gone", from: DevelopSettings()), adapts: false, in: workflows)

        await WorkflowMigration.run(workflows: workflows, into: store)

        let recipes = await store.all()
        // The workflow with the recipe's name took its place; the other stands beside it.
        #expect(recipes.map(\.name) == ["Ektar", "Ektar for print", "Untouched"])
        #expect(recipes.map(\.id) == [same, web, untouched.id])
        let adapting = recipes[0]
        #expect(adapting.look.filmID == "kodak_ektar_100" && adapting.look.autoExposure && adapting.look.autoWhiteBalance)
        #expect(adapting.filmModel == "0.0.1")
        #expect(adapting.files == RecipeFiles(
            options: ExportOptions(format: .tiff), naming: .nameAndText("print"),
            destination: .besideOriginals(folderName: "Prints"), asks: [.destination],
        ))
        // One kept before workflows adapted is given as its recipe was, its files named as they were.
        #expect(!recipes[1].look.autoExposure && !recipes[1].look.autoWhiteBalance)
        #expect(recipes[1].files.naming == .nameAndFilm && recipes[1].files.asks.isEmpty)
        #expect(recipes[2] == untouched)
        #expect(!FileManager.default.fileExists(atPath: workflows.path))

        // Nothing is left to do a second time.
        await WorkflowMigration.run(workflows: workflows, into: store)
        #expect(await store.all() == recipes)
    }

    @Test func aWorkflowThatCannotBeReadIsLeftWhereItIs() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecipeStore(directory: folder.appendingPathComponent("recipes"))
        let workflows = folder.appendingPathComponent("workflows")
        try FileManager.default.createDirectory(at: workflows, withIntermediateDirectories: true)
        let junk = workflows.appendingPathComponent("junk.json")
        try Data("not json".utf8).write(to: junk)

        await WorkflowMigration.run(workflows: workflows, into: store)

        #expect(await store.all().isEmpty)
        #expect(try Data(contentsOf: junk) == Data("not json".utf8))
    }
}
