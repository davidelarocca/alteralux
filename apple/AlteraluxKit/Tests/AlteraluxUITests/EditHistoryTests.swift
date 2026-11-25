import AlteraluxKit
import Foundation
import Synchronization
import Testing
@testable import AlteraluxUI

/// The adjustments of a photo kept between launches, and their undo.
@MainActor
struct EditHistoryTests {
    /// Test pictures in a folder of their own, and a place for the adjustments of photos that
    /// cannot be written. The caller removes the folder.
    private struct Fixture {
        let folder: URL
        let photos: [URL]

        @MainActor
        init(count: Int = 1) throws {
            photos = try WindowedTests.writeTestPictures(count: count)
            folder = photos[0].deletingLastPathComponent()
        }

        /// A model as a launch of the app gives it, with an undo manager of its own.
        @MainActor
        func model() -> AppModel {
            let model = AppModel(
                dataDirectory: WindowedTests.engineData, editsDirectory: folder.appendingPathComponent("edits"),
            )
            let undoManager = UndoManager()
            // No run loop groups the steps here: each change opens and closes its own.
            undoManager.groupsByEvent = false
            model.history.undoManager = undoManager
            return model
        }

        func remove() {
            for photo in photos {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: photo.path)
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Makes one change, as a control does, and waits for it to stand still and be kept.
    private func change(_ model: AppModel, _ edit: (inout DevelopSettings) -> Void) async throws {
        edit(&model.settings)
        model.settingsDidChange()
        try await settle(model)
    }

    /// Ends the change in progress without waiting for the settings to stand still.
    private func settle(_ model: AppModel) async throws {
        model.settleChange()
        await model.history.waitUntilSaved()
    }

    private func wait(_ what: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func adjustmentsComeBackWhenThePhotoIsOpenedAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.model()
        first.open(fixture.photos)
        try await change(first) {
            $0.exposureEV = 0.7
            $0.filmID = "fujifilm_velvia_100"
            $0.scanFilm = true
        }

        // Another launch: nothing in memory, only what the photo carries.
        let second = fixture.model()
        second.open(fixture.photos)
        #expect(second.settings.exposureEV == 0.7)
        #expect(second.settings.filmID == "fujifilm_velvia_100" && second.settings.scanFilm)
        // The photo carries them itself: nothing is in the app's folder.
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edits").path))
    }

    /// Nothing asks for the adjustments to be kept: standing still for a moment is enough.
    @Test func adjustmentsAreKeptOnceTheyStandStill() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        model.settings.exposureEV = 0.7
        model.settingsDidChange()
        try await wait("the adjustments to be kept") { model.history.kept(for: fixture.photos[0]) != nil }
        #expect(model.history.kept(for: fixture.photos[0])?.exposureEV == 0.7)
    }

    /// The strip marks the photos that have adjustments kept with them, as the library's grid
    /// does: one only opened has none, one adjusted has, and so it is after another launch.
    @Test func aPhotoOfTheStripSaysWhetherItHasAdjustments() async throws {
        let fixture = try Fixture(count: 2)
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        #expect(model.photos.allSatisfy { !$0.hasAdjustments })
        try await change(model) { $0.exposureEV = 0.7 }
        #expect(model.photos[0].hasAdjustments && !model.photos[1].hasAdjustments)

        // Adjustments given away from the develop screen, as a recipe from the library, and
        // taken back.
        model.set([PhotoAdjustments(photo: fixture.photos[1], settings: DevelopSettings(exposureEV: 1), isKept: true)])
        #expect(model.photos[1].hasAdjustments)
        model.history.undo()
        #expect(!model.photos[1].hasAdjustments)
        await model.history.waitUntilSaved()

        // Another launch: the mark comes from what each photo carries.
        let second = fixture.model()
        second.open(fixture.photos)
        #expect(second.photos[0].hasAdjustments && !second.photos[1].hasAdjustments)
    }

    @Test func aPhotoThatWasOnlyLookedAtIsNotWritten() async throws {
        let fixture = try Fixture(count: 2)
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        model.selectAdjacent(offset: 1)
        model.selectAdjacent(offset: -1)
        // A change taken back before it stands still leaves nothing to keep either.
        model.settings.exposureEV = 1
        model.settingsDidChange()
        model.settings.exposureEV = 0
        model.settingsDidChange()
        try await settle(model)
        model.removeSelection()
        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: fixture.photos[0]) == nil)
        #expect(model.history.kept(for: fixture.photos[1]) == nil)
    }

    @Test func aPhotoThatCannotBeWrittenKeepsItsAdjustmentsInTheAppsFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fixture.photos[0].path)
        let first = fixture.model()
        first.open(fixture.photos)
        try await change(first) { $0.exposureEV = -1.2 }
        #expect(first.alertMessage == nil)

        let second = fixture.model()
        second.open(fixture.photos)
        #expect(second.settings.exposureEV == -1.2)
    }

    /// Adjustments that could not be written are not taken for kept: they are written the next
    /// time the photo settles.
    @Test func adjustmentsThatCouldNotBeKeptAreTriedAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // Nowhere to keep them: the photo cannot be written, and the folder for those is a file.
        let blocked = fixture.folder.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fixture.photos[0].path)
        let model = AppModel(
            dataDirectory: WindowedTests.engineData, editsDirectory: blocked.appendingPathComponent("edits"),
        )
        model.open(fixture.photos)
        try await change(model) { $0.exposureEV = 0.7 }
        #expect(model.alertMessage != nil)
        #expect(model.history.kept(for: fixture.photos[0]) == nil)

        // The photo can be written again; nothing changes but the photo leaving the strip.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.photos[0].path)
        model.removeSelection()
        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: fixture.photos[0])?.exposureEV == 0.7)
    }

    @Test func aChangeMadeWhileSelectingAnotherPhotoIsKept() async throws {
        let fixture = try Fixture(count: 2)
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        model.settings.exposureEV = 0.4
        model.settingsDidChange()
        // Before the change has stood still.
        model.selectAdjacent(offset: 1)
        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: fixture.photos[0])?.exposureEV == 0.4)
    }

    /// A drag gives many values: undo takes back the whole of it, not its last frame.
    @Test func undoTakesBackAWholeChange() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        #expect(!model.canUndo && !model.canRedo)

        for value in [0.1, 0.2, 0.3] {
            model.settings.exposureEV = value
            model.settingsDidChange()
        }
        try await settle(model)
        try await change(model) { $0.grainEnabled = false }
        try await wait("something to undo") { model.canUndo }

        model.undo()
        #expect(model.settings.grainEnabled && model.settings.exposureEV == 0.3)
        model.undo()
        #expect(model.settings.exposureEV == 0)
        try await wait("nothing left to undo") { !model.canUndo && model.canRedo }

        model.redo()
        #expect(model.settings.exposureEV == 0.3 && model.settings.grainEnabled)
        model.redo()
        #expect(!model.settings.grainEnabled)
        try await wait("nothing left to redo") { model.canUndo && !model.canRedo }

        // What is undone is what the photo keeps.
        model.undo()
        try await settle(model)
        let kept = try #require(model.history.kept(for: fixture.photos[0]))
        #expect(kept.grainEnabled && kept.exposureEV == 0.3)
        // A new change leaves nothing to redo.
        try await change(model) { $0.halationAmount = 2 }
        try await wait("no redo after a change") { !model.canRedo }
    }

    @Test func resetAndAFilmChosenAreUndoneWhole() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.start()
        model.open(fixture.photos)
        try await change(model) {
            $0.exposureEV = 1.5
            $0.grainEnabled = false
        }

        model.resetAdjustments()
        model.settingsDidChange()
        try await settle(model)
        #expect(model.settings.exposureEV == 0 && model.settings.grainEnabled)
        model.undo()
        #expect(model.settings.exposureEV == 1.5 && !model.settings.grainEnabled)

        // Choosing a film changes the film, the paper and the scan together.
        let before = model.settings
        model.chooseFilm("fujifilm_velvia_100")
        model.settingsDidChange()
        try await settle(model)
        #expect(model.settings.scanFilm)
        model.undo()
        #expect(model.settings == before)
    }

    @Test func undoGoesBackToThePhotoThatWasChanged() async throws {
        let fixture = try Fixture(count: 2)
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        let first = try #require(model.selection)
        try await change(model) { $0.exposureEV = 0.9 }
        model.selectAdjacent(offset: 1)
        #expect(model.selection !== first)

        model.undo()
        #expect(model.selection === first)
        #expect(model.settings.exposureEV == 0 && first.settings.exposureEV == 0)
        model.redo()
        #expect(model.selection === first && model.settings.exposureEV == 0.9)
    }

    @Test func aPhotoRemovedFromTheStripLeavesNothingToUndo() async throws {
        let fixture = try Fixture(count: 2)
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        try await change(model) { $0.exposureEV = 0.9 }
        try await wait("something to undo") { model.canUndo }

        model.removeSelection()
        try await wait("nothing to undo") { !model.canUndo }
        model.undo()
        #expect(model.settings.exposureEV == 0)
        // What was done to it stays with the photo.
        await model.history.waitUntilSaved()
        #expect(model.history.kept(for: fixture.photos[0])?.exposureEV == 0.9)
    }

    /// Reading whether there is something to redo makes the undo manager post a checkpoint. A
    /// history that refreshed on every checkpoint asked for the next one without end: after the
    /// first step the app kept a core busy until it was quit.
    @Test func theUndoManagerIsLeftAloneOnceAStepIsDone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        model.open(fixture.photos)
        try await change(model) { $0.exposureEV = 0.5 }
        try await wait("something to undo") { model.canUndo }

        let checkpoints = Mutex(0)
        let observer = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerCheckpoint, object: model.history.undoManager, queue: nil,
        ) { _ in checkpoints.withLock { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(checkpoints.withLock { $0 } == 0)
    }
}
