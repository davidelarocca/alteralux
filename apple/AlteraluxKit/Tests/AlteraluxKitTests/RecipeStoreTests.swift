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

    @Test func whetherARecipeAdaptsIsKept() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var recipe = Recipe(name: "Portra di sera", from: DevelopSettings())
        #expect(!recipe.adaptsToEachPhoto)
        recipe.adaptsToEachPhoto = true
        try await fixture.store.save(recipe)
        #expect(try #require(await fixture.store.all().first).adaptsToEachPhoto)
    }

    @Test func aRecipeThatAdaptsMetersEachPhotoAndBalancesItsWhite() {
        var look = DevelopSettings(filmID: "kodak_ektar_100")
        look.autoExposure = false
        look.exposureEV = 0.7
        let recipe = Recipe(name: "Ektar", from: look, adaptsToEachPhoto: true)
        let given = recipe.applied(to: DevelopSettings())
        #expect(given.filmID == "kodak_ektar_100" && given.exposureEV == 0.7)
        #expect(given.autoExposure && given.autoWhiteBalance)

        // A white balance chosen by hand stays.
        let chosen = DevelopSettings(temperature: 3200, tint: 4)
        let kept = recipe.applied(to: chosen)
        #expect(kept.temperature == 3200 && kept.tint == 4 && !kept.autoWhiteBalance)

        // A recipe that does not adapt leaves the photo's white balance and exposure as the look has them.
        let plain = Recipe(name: "Ektar", from: look)
        let plainGiven = plain.applied(to: DevelopSettings())
        #expect(!plainGiven.autoExposure && !plainGiven.autoWhiteBalance)
    }

    @Test func aRecipeLeavesThePhotosLensCorrection() {
        let recipe = Recipe(name: "Senza correzione", from: DevelopSettings(lensCorrection: false))
        #expect(recipe.applied(to: DevelopSettings()).lensCorrection == true)
        #expect(recipe.applied(to: DevelopSettings(lensCorrection: nil)).lensCorrection == nil)
    }
}

/// Keeping workflows between launches, in the same way as recipes.
struct WorkflowStoreTests {
    @Test func aWorkflowIsReadBackAndItsFileNamesWhatItHolds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("Output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = WorkflowStore(directory: folder.appendingPathComponent("workflows"))
        let beside = Workflow(name: "Web", recipeID: UUID(), destination: .besideOriginals(folderName: "Web"))
        let chosen = try Workflow(
            name: "Print", recipeID: UUID(), options: ExportOptions(format: .tiff, longSide: 4096),
            destination: .folder(FolderBookmark(for: output)),
        )
        try await store.save(beside)
        try await store.save(chosen)
        #expect(await WorkflowStore(directory: folder.appendingPathComponent("workflows")).all() == [chosen, beside])

        let file = folder.appendingPathComponent("workflows/\(beside.id.uuidString).json")
        let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(stored["version"] as? Int == 1 && stored["workflow"] != nil)

        // The bookmark finds the folder again.
        if case let .folder(bookmark) = chosen.destination {
            #expect(bookmark.resolve()?.standardizedFileURL.path == output.standardizedFileURL.path)
            #expect(bookmark.name == "Output")
        }
    }
}
