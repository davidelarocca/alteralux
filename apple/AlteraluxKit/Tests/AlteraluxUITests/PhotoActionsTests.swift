import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// The actions of a photo's menu in the library: turning, resetting, duplicating, renaming.
@MainActor
struct PhotoActionsTests {
    /// A folder with three wide photos (2:1), added to a library of its own; the caller removes
    /// the folder.
    @MainActor
    private struct Fixture {
        let root: URL
        let shoot: URL

        init() throws {
            let pictures = try WindowedTests.writeTestPictures(count: 3)
            root = pictures[0].deletingLastPathComponent()
            shoot = root.appendingPathComponent("Shoot")
            try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
            for picture in pictures {
                try FileManager.default.moveItem(at: picture, to: shoot.appendingPathComponent(picture.lastPathComponent))
            }
        }

        func model() async -> AppModel {
            let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: root.appendingPathComponent("support"))
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            model.history.undoManager = undoManager
            await model.addFolder(shoot)
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

    @Test func turningPhotosTurnsTheirThumbnailsAndUndoTurnsThemBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = await fixture.model()
        let photos = model.library.photos
        #expect(model.library.shownAspectRatio(of: photos[0]) == 2)

        model.library.click(photos[0])
        model.library.click(photos[1], toggling: true)
        model.turnSelection(clockwise: true)

        #expect(model.history.kept(for: photos[0])?.crop?.quarterTurns == 1)
        #expect(model.history.kept(for: photos[2]) == nil)
        try await wait("the turned thumbnails") { model.library.crops.keys.sorted { $0.path < $1.path } == [photos[0], photos[1]] }
        // Upright now: the grid gives it an upright tile.
        #expect(model.library.shownAspectRatio(of: photos[0]) == 0.5)

        model.undo()
        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: photos[0]) == nil)
        try await wait("the thumbnails turned back") { model.library.crops.isEmpty }
    }

    @Test func resettingTakesTheAdjustmentsAwayAndUndoGivesThemBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = await fixture.model()
        let photos = model.library.photos
        model.library.click(photos[0])
        model.turnSelection(clockwise: false)
        try await wait("the mark") { model.library.adjusted == [photos[0]] }

        model.resetAdjustmentsOfSelection()

        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: photos[0]) == nil)
        try await wait("the mark to go") { model.library.adjusted.isEmpty && model.library.crops.isEmpty }
        model.undo()
        #expect(model.history.kept(for: photos[0])?.crop?.quarterTurns == 3)
        try await wait("the mark back") { model.library.adjusted == [photos[0]] }
    }

    @Test func aDuplicateKeepsTheAdjustmentsAndBecomesTheSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = await fixture.model()
        let photo = model.library.photos[0]
        model.library.click(photo)
        model.turnSelection(clockwise: true)
        await model.history.waitUntilSaved()

        await model.duplicateSelection()

        #expect(model.library.photos.count == 4)
        let copy = try #require(model.library.selection.first)
        #expect(model.library.selection.count == 1 && copy.lastPathComponent == "Picture 1 copy.png")
        #expect(model.history.kept(for: copy)?.crop?.quarterTurns == 1)
        #expect(model.library.adjusted.contains(copy))
    }

    @Test func aRenamedPhotoStaysSelectedAndUndoGivesBackItsName() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = await fixture.model()
        let photo = model.library.photos[0]
        model.library.click(photo)

        await model.rename(photo, to: "Sunset")

        let renamed = fixture.shoot.appendingPathComponent("Sunset.png")
        #expect(model.library.selection.map(\.lastPathComponent) == ["Sunset.png"])
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(!model.library.photos.contains(photo))

        model.undo()
        try await wait("the old name") { model.library.photos.map(\.lastPathComponent).contains("Picture 1.png") }
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
    }
}
