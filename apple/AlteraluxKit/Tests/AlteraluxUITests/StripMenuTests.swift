import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// The menu of a photo of the strip: it acts on that photo, and the photo on screen stays.
@MainActor
struct StripMenuTests {
    /// A folder with four photos, added to a library of its own and developed from its first
    /// photo, and one more photo outside the library; the caller removes them.
    @MainActor
    private struct Fixture {
        let root: URL
        let shoot: URL
        let outside: URL

        init() throws {
            let pictures = try WindowedTests.writeTestPictures(count: 5)
            root = pictures[0].deletingLastPathComponent()
            shoot = root.appendingPathComponent("Shoot")
            try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
            for picture in pictures.dropLast() {
                try FileManager.default.moveItem(at: picture, to: shoot.appendingPathComponent(picture.lastPathComponent))
            }
            outside = pictures[4]
        }

        /// A model with the folder's photos in the strip, the first on screen.
        func model() async throws -> AppModel {
            let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: root.appendingPathComponent("support"))
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            model.history.undoManager = undoManager
            await model.addFolder(shoot)
            try model.develop(#require(model.library.photos.first))
            return model
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func wait(_ what: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func adjustmentsAreCopiedPastedAndResetOnThePhotoOfTheMenu() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = try await fixture.model()
        let (first, third) = (model.photos[0], model.photos[2])

        // The photo on screen gets a look; it is copied from its thumbnail, the change still open.
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        model.copyAdjustments(of: first)
        #expect(model.copiedAdjustments?.exposureEV == 0.5)

        // Pasted on another thumbnail: that photo has the look and its mark, the one on screen stays.
        model.pasteAdjustments(on: third)
        #expect(model.selection === first)
        #expect(third.settings.exposureEV == 0.5 && third.hasAdjustments)
        #expect(model.history.kept(for: third.url)?.exposureEV == 0.5)
        model.undo()
        #expect(third.settings.exposureEV == 0 && !third.hasAdjustments)
        model.redo()
        #expect(third.hasAdjustments)

        // Reset from its thumbnail: a photo never developed again, as in the library.
        #expect(model.canResetAdjustments(of: third))
        model.resetAdjustments(of: third)
        #expect(third.settings == DevelopSettings() && !third.hasAdjustments)
        #expect(model.history.kept(for: third.url) == nil)
        #expect(!model.canResetAdjustments(of: third))
        #expect(model.selection === first && model.settings.exposureEV == 0.5)

        // The photo on screen keeps its film, as its own Reset does, and one undo gives back its look.
        model.settings.filmID = "kodak_gold_200"
        model.settingsDidChange()
        model.resetAdjustments(of: first)
        #expect(model.settings.exposureEV == 0 && model.settings.filmID == "kodak_gold_200")
        model.undo()
        #expect(model.settings.exposureEV == 0.5)
    }

    @Test func aPhotoDiscardedFromTheStripStaysThereWithItsMark() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = try await fixture.model()
        let second = model.photos[1]

        #expect(model.canDiscard(second) && !model.isDiscarded(second))
        model.toggleDiscarded(second)
        #expect(model.isDiscarded(second))
        #expect(model.library.discarded == [second.url])
        #expect(model.photos.count == 4 && model.selection === model.photos[0])

        // Taken back from the same menu, and by undo.
        model.toggleDiscarded(second)
        #expect(!model.isDiscarded(second))
        model.undo()
        #expect(model.isDiscarded(second))

        // A photo opened from outside the library is not in a folder to be hidden from.
        model.open([fixture.outside])
        let outside = try #require(model.photos.last)
        #expect(outside.url == fixture.outside && !model.canDiscard(outside))
    }

    @Test func aPhotoMovedToTheTrashLeavesTheStrip() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = try await fixture.model()
        let urls = model.photos.map(\.url)

        // A photo that is not on screen: the one on screen stays.
        await model.trash([urls[2]])
        #expect(model.alertMessage == nil)
        #expect(model.photos.map(\.url) == [urls[0], urls[1], urls[3]])
        #expect(model.selection?.url == urls[0])
        #expect(!FileManager.default.fileExists(atPath: urls[2].path))
        #expect(model.library.photos.count == 3)

        // The photo on screen, a change still open: the next one takes its place.
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        await model.trash([urls[0]])
        #expect(model.photos.map(\.url) == [urls[1], urls[3]])
        #expect(model.selection?.url == urls[1])
        #expect(model.settings.exposureEV == 0)
    }

    @Test func tagsArePutOnThePhotoOfTheMenuAndShownInTheStrip() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = try await fixture.model()
        let second = model.photos[1]

        model.toggleTag("Red", color: .red, on: [second.url])
        try await wait("the tag on the photo of the library") { model.tags(of: second) == [FinderTag(name: "Red", color: .red)] }
        #expect(model.tags(of: model.photos[0]).isEmpty)
        #expect(model.tagChoices(for: [second.url]).first { $0.name == "Red" }?.carriedBy == 1)
        model.toggleTag("Red", color: .red, on: [second.url])
        try await wait("the tag taken off") { model.tags(of: second).isEmpty }

        // A photo the library does not list carries its tags itself.
        model.open([fixture.outside])
        let outside = try #require(model.photos.last)
        model.addTag(named: "Portfolio", color: .blue, to: [outside.url])
        try await wait("the tag on the photo outside the library") {
            model.tags(of: outside) == [FinderTag(name: "Portfolio", color: .blue)]
        }
    }

    @Test func exportingFromAThumbnailAsksForThatPhoto() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = try await fixture.model()
        await model.start()
        let third = model.photos[2]

        #expect(model.canPresentExport(of: third))
        model.presentExport(of: third)
        #expect(model.isExportPresented && model.photosToExport == [third.url])
        #expect(model.selection === model.photos[0])
    }
}
