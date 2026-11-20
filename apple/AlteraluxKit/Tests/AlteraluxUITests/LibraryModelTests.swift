import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// The library: folders added, shown as they are on disk.
@MainActor
struct LibraryModelTests {
    /// A folder of test pictures with a subfolder, and where a model keeps what it remembers.
    private struct Fixture {
        let root: URL
        let shoot: URL
        let store: EditStore

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
            shoot = root.appendingPathComponent("Shoot")
            let selects = shoot.appendingPathComponent("Selects")
            try FileManager.default.createDirectory(at: selects, withIntermediateDirectories: true)
            for name in ["IMG_10.jpg", "IMG_2.jpg", "IMG_1.jpg", "notes.txt"] {
                try Data("x".utf8).write(to: shoot.appendingPathComponent(name))
            }
            try Data("x".utf8).write(to: selects.appendingPathComponent("IMG_7.jpg"))
            store = EditStore(fallbackDirectory: root.appendingPathComponent("edits"))
        }

        /// A model as a launch of the app gives it.
        @MainActor
        func model() -> LibraryModel {
            LibraryModel(
                storeURL: root.appendingPathComponent("support/folders.plist"), cacheDirectory: nil,
                discards: DiscardStore(fallbackDirectory: root.appendingPathComponent("support/discarded")),
                hasAdjustments: { [store] in store.hasAdjustments(for: $0) },
            )
        }

        func photo(_ name: String) -> URL {
            shoot.appendingPathComponent(name)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent)
    }

    private func wait(_ what: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aFolderAddedShowsItsPhotosAsTheFinderOrdersThem() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.load()
        #expect(model.isEmpty && model.selectedFolder == nil)

        try await model.add(fixture.shoot)
        #expect(model.roots.count == 1)
        #expect(model.selectedFolder == fixture.shoot)
        #expect(names(model.photos) == ["IMG_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
        let tree = try #require(model.roots.first?.tree)
        #expect(tree.photoCount == 3)
        #expect(tree.children.map(\.name) == ["Selects"] && tree.children.first?.photoCount == 1)
        #expect(model.selectedNode?.photoCount == 3)
        // Adding it again adds nothing.
        try await model.add(fixture.shoot)
        #expect(model.roots.count == 1)
    }

    @Test func theFoldersAreRememberedByTheNextLaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.model()
        try await first.add(fixture.shoot)

        let second = fixture.model()
        await second.load()
        #expect(second.roots.map(\.folder.url.lastPathComponent) == ["Shoot"])
        #expect(second.selectedFolder?.lastPathComponent == "Shoot")
        #expect(names(second.photos) == ["IMG_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
    }

    @Test func aFolderInsideIsShownOnItsOwn() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        model.selection = Set(model.photos.prefix(1))

        let selects = try #require(model.roots.first?.tree?.children.first?.url)
        await model.select(selects)
        #expect(names(model.photos) == ["IMG_7.jpg"])
        #expect(model.selectedNode?.name == "Selects")
        // The selection belonged to the folder before.
        #expect(model.selection.isEmpty)
    }

    @Test func theFilterKeepsThePhotosWithAdjustments() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.store.save(DevelopSettings(exposureEV: 0.5), for: fixture.photo("IMG_2.jpg"))
        let model = fixture.model()
        try await model.add(fixture.shoot)
        #expect(names(Array(model.adjusted)) == ["IMG_2.jpg"])

        // The grid selects the photos as the folder lists them.
        model.selection = Set(model.photos.filter { $0.lastPathComponent != "IMG_10.jpg" })
        #expect(model.selection.count == 2)
        model.filter = .adjusted
        #expect(names(model.visiblePhotos) == ["IMG_2.jpg"])
        // What the filter hides is no longer selected.
        #expect(names(Array(model.selection)) == ["IMG_2.jpg"])
        model.filter = .all
        #expect(model.visiblePhotos.count == 3)

        // A photo adjusted while the folder is on screen gets its mark without reading it again.
        try await fixture.store.save(DevelopSettings(exposureEV: 1), for: fixture.photo("IMG_10.jpg"))
        model.noteAdjustments(of: fixture.photo("IMG_10.jpg"))
        #expect(model.adjusted.count == 2)
    }

    @Test func aClickSelectsAndTheKeysMoveThroughThePhotos() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        let photos = model.photos

        model.click(photos[0])
        #expect(model.selection == [photos[0]])
        // Command adds and takes away, Shift takes everything up to the photo.
        model.click(photos[2], toggling: true)
        #expect(model.selection == [photos[0], photos[2]])
        model.click(photos[2], toggling: true)
        #expect(model.selection == [photos[0]])
        model.click(photos[0])
        model.click(photos[2], extending: true)
        #expect(model.selection == Set(photos))
        model.click(photos[1])
        #expect(model.selection == [photos[1]] && model.focusedPhoto == photos[1])

        model.moveSelection(by: 1)
        #expect(model.selection == [photos[2]])
        model.moveSelection(by: 1)
        #expect(model.selection == [photos[2]])
        model.moveSelection(by: -5)
        #expect(model.selection == [photos[0]] && model.focusedPhoto == photos[0])
        model.selectAll()
        #expect(model.selection.count == 3)
        model.clearSelection()
        #expect(model.selection.isEmpty && model.focusedPhoto == nil)
    }

    /// The order and the kinds shown are kept for the next launch; the filter of adjusted and
    /// discarded photos is not.
    @Test func theOrderAndTheKindsShownAreKeptForTheNextLaunch() throws {
        let suite = "alteralux-tests-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        func launch() -> LibraryModel {
            LibraryModel(
                storeURL: root.appendingPathComponent("folders.plist"), cacheDirectory: nil,
                discards: DiscardStore(fallbackDirectory: root.appendingPathComponent("discarded")),
                preferences: preferences, hasAdjustments: { _ in false },
            )
        }

        let first = launch()
        #expect(first.sort == .name && first.sortsAscending && first.kinds == .all)
        first.sort = .date
        first.sortsAscending = false
        first.kinds = .raw
        first.filter = .discarded

        let next = launch()
        #expect(next.sort == .date && !next.sortsAscending && next.kinds == .raw)
        #expect(next.filter == .all)
    }

    /// Shift with the arrow keys grows the selection from the photo it started on, and the keys
    /// go on from the photo they reached.
    @Test func shiftAndTheArrowsGrowTheSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        let photos = model.photos

        model.click(photos[0])
        model.moveSelection(by: 1, extending: true)
        #expect(model.selection == [photos[0], photos[1]] && model.focusedPhoto == photos[1])
        model.moveSelection(by: 1, extending: true)
        #expect(model.selection == Set(photos) && model.focusedPhoto == photos[2])
        // Without Shift the keys go on from where they were, with that photo alone.
        model.moveSelection(by: -1)
        #expect(model.selection == [photos[1]])
        // To the first photo, as Home does.
        model.moveSelection(by: -photos.count)
        #expect(model.selection == [photos[0]])
    }

    /// A rectangle dragged over the grid selects what it covers, as in the Finder.
    @Test func aRectangleDraggedOverThePhotosSelectsThem() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        let photos = model.photos

        model.click(photos[0])
        // Alone, the rectangle replaces the selection, and the keys go on from its first photo.
        model.select(covered: [photos[2], photos[1]])
        #expect(model.selection == [photos[1], photos[2]] && model.focusedPhoto == photos[1])
        // With Shift it adds to what was selected; with Command it takes away what it covers twice.
        model.select(covered: [photos[0]], before: [photos[2]])
        #expect(model.selection == [photos[0], photos[2]])
        model.select(covered: [photos[1], photos[2]], before: [photos[0], photos[2]], toggling: true)
        #expect(model.selection == [photos[0], photos[1]])
        // A rectangle over nothing, alone, leaves nothing selected.
        model.select(covered: [])
        #expect(model.selection.isEmpty)
    }

    /// Discarding marks a photo and hides it; the file stays until the discarded are emptied.
    @Test func discardedPhotosAreHiddenAndStillOnDisk() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        let photos = model.photos

        model.selection = [photos[0], photos[1]]
        #expect(model.setDiscarded(true, for: [photos[0]]) == [photos[0]])
        #expect(names(model.visiblePhotos) == ["IMG_2.jpg", "IMG_10.jpg"])
        // What is hidden is no longer selected.
        #expect(model.selection == [photos[1]])
        #expect(FileManager.default.fileExists(atPath: photos[0].path))
        model.filter = .discarded
        #expect(names(model.visiblePhotos) == ["IMG_1.jpg"])

        // The mark is in the photo: another launch finds it.
        let next = fixture.model()
        await next.load()
        #expect(names(Array(next.discarded)) == ["IMG_1.jpg"])
        #expect(next.visiblePhotos.count == 2)

        // Restored, it is back among the others.
        model.setDiscarded(false, for: [photos[0]])
        #expect(model.discarded.isEmpty && model.visiblePhotos.isEmpty)
        model.filter = .all
        #expect(model.visiblePhotos.count == 3)
    }

    @Test func emptyingTheDiscardedPhotosSendsThemToTheTrash() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        let photos = model.photos
        model.setDiscarded(true, for: [photos[0]])

        let results = await model.emptyDiscarded()
        #expect(results.count == 1 && results.allSatisfy { $0.succeeded })
        #expect(!FileManager.default.fileExists(atPath: photos[0].path))
        #expect(names(model.photos) == ["IMG_2.jpg", "IMG_10.jpg"] && model.discarded.isEmpty)
        // The test's own file does not stay in the Trash.
        for trashed in results.compactMap(\.destination) {
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    @Test func photosAreMovedAndCopiedBetweenTheLibrarysFolders() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        #expect(model.destinations.map(\.name) == ["Shoot", "Selects"])
        let selects = try #require(model.destinations.last?.url)
        let photos = model.photos

        let moved = await model.move([photos[0]], to: selects)
        #expect(moved.allSatisfy { $0.succeeded })
        #expect(names(model.photos) == ["IMG_2.jpg", "IMG_10.jpg"])
        #expect(model.roots.first?.tree?.children.first?.photoCount == 2)

        let copied = await model.copy([photos[1]], to: selects)
        #expect(copied.allSatisfy { $0.succeeded })
        #expect(model.photos.count == 2)
        #expect(model.roots.first?.tree?.children.first?.photoCount == 3)
    }

    @Test func tagsAreTheFindersAndASelectionShowsHowManyCarryEach() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        let photos = model.photos

        #expect(model.setTag(FinderTag(name: "Portfolio"), isOn: true, for: [photos[0], photos[1]]).allSatisfy { $0.succeeded })
        model.selection = Set(photos)
        #expect(model.tagsOfSelection() == ["Portfolio": 2])
        model.setTag(FinderTag(name: "Portfolio"), isOn: false, for: [photos[0]])
        #expect(model.tagsOfSelection() == ["Portfolio": 1])
    }

    @Test func whatChangesOnDiskShowsInTheLibrary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)

        try Data("x".utf8).write(to: fixture.photo("IMG_3.jpg"))
        try await wait("the new photo") { model.photos.count == 4 }
        #expect(names(model.photos) == ["IMG_1.jpg", "IMG_2.jpg", "IMG_3.jpg", "IMG_10.jpg"])
        #expect(model.roots.first?.tree?.photoCount == 4)

        try FileManager.default.removeItem(at: fixture.photo("IMG_1.jpg"))
        try await wait("the photo to go") { model.photos.count == 3 }
    }

    @Test func aFolderForgottenLeavesTheDiskAsItIs() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        let id = try #require(model.roots.first?.id)

        await model.remove(id)
        #expect(model.isEmpty && model.selectedFolder == nil && model.photos.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.photo("IMG_1.jpg").path))
        let next = fixture.model()
        await next.load()
        #expect(next.isEmpty)
    }

    @Test func aFolderThatIsGoneStaysInTheListWithoutContents() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.model()
        try await first.add(fixture.shoot)
        try FileManager.default.removeItem(at: fixture.shoot)

        let second = fixture.model()
        await second.load()
        #expect(second.roots.count == 1)
        #expect(second.roots.first?.tree == nil && second.roots.first?.folder.isAvailable == false)
        #expect(second.selectedFolder == nil && second.photos.isEmpty)
    }
}

/// The library and the photo being developed, in one window.
@MainActor
struct LibraryInTheAppTests {
    /// A folder of four test pictures, and where a model keeps what it remembers.
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

        /// A model as a launch of the app gives it.
        @MainActor
        func model() -> AppModel {
            AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: root.appendingPathComponent("support"))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func wait(_ what: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aFolderAddedOpensTheLibraryAndTheNextLaunchStartsThere() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.model()
        await first.start()
        #expect(!first.showsLibrary && !first.hasLibrary)

        await first.addFolder(fixture.shoot)
        #expect(first.showsLibrary && first.hasLibrary)
        #expect(first.library.photos.count == 4)

        let second = fixture.model()
        await second.start()
        #expect(second.showsLibrary)
        #expect(second.library.photos.count == 4)
    }

    @Test func aPhotoOfAFolderIsDevelopedWithTheFolderInTheStrip() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.addFolder(fixture.shoot)
        let photos = model.library.photos

        model.develop(photos[2])
        #expect(!model.showsLibrary)
        #expect(model.photos.map(\.url) == photos)
        #expect(model.selection?.url == photos[2])
        // Previous and next walk the folder.
        model.selectAdjacent(offset: 1)
        #expect(model.selection?.url == photos[3])

        // Back in the library, another photo: the strip is the same folder, not twice.
        model.showLibrary()
        #expect(model.showsLibrary)
        model.develop(photos[0])
        #expect(model.photos.map(\.url) == photos && model.selection?.url == photos[0])
    }

    @Test func onlyThePhotosShownGoToTheStrip() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.addFolder(fixture.shoot)
        let photos = model.library.photos

        // One photo gets adjustments, and its mark in the grid.
        model.develop(photos[1])
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        model.showLibrary()
        try await wait("the mark on the adjusted photo") { model.library.adjusted == [photos[1]] }

        model.library.filter = .adjusted
        model.develop(photos[1])
        #expect(model.photos.map(\.url) == [photos[1]])
        #expect(model.settings.exposureEV == 0.5)
    }

    @Test func discardingTheSelectionCanBeUndone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.history.undoManager = undoManager
        await model.addFolder(fixture.shoot)
        let photos = model.library.photos

        model.library.click(photos[0])
        model.library.click(photos[1], toggling: true)
        #expect(model.selectedPhotos == [photos[0], photos[1]])
        model.discardSelection()
        #expect(model.library.visiblePhotos == [photos[2], photos[3]])
        #expect(model.library.selection.isEmpty)

        model.undo()
        #expect(model.library.discarded.isEmpty && model.library.visiblePhotos.count == 4)
        model.redo()
        #expect(model.library.discarded == [photos[0], photos[1]])

        // Under their own filter, the same command takes the photos back.
        model.library.filter = .discarded
        model.library.click(photos[0])
        model.discardSelection()
        #expect(model.library.discarded == [photos[1]])
    }

    @Test func movingTheSelectionCanBeUndoneAndTagsAreToggled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let other = fixture.root.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let model = fixture.model()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.history.undoManager = undoManager
        await model.addFolder(other)
        await model.addFolder(fixture.shoot)
        let photos = model.library.photos
        let destination = try #require(model.library.destinations.first { $0.name == "Other" }?.url)

        model.library.click(photos[0])
        model.toggleTag("Portfolio")
        #expect(model.tagChoices.first { $0.name == "Portfolio" }?.carriedBy == 1)
        model.toggleTag("Portfolio")
        #expect(model.library.tagsOfSelection().isEmpty)

        await model.moveSelection(to: destination)
        #expect(model.alertMessage == nil)
        #expect(model.library.photos.count == 3)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(photos[0].lastPathComponent).path))

        model.undo()
        try await wait("the photo to come back") { model.library.photos.count == 4 }
        #expect(model.library.photos.map(\.lastPathComponent) == photos.map(\.lastPathComponent))
    }

    @Test func foldersGoToTheLibraryAndPhotosAreOpened() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let loose = try WindowedTests.writeTestPictures(count: 1)
        defer { try? FileManager.default.removeItem(at: loose[0].deletingLastPathComponent()) }
        let model = fixture.model()

        model.take([fixture.shoot])
        try await wait("the folder in the library") { model.hasLibrary && model.showsLibrary }
        #expect(model.photos.isEmpty)

        model.take(loose)
        #expect(!model.showsLibrary)
        #expect(model.photos.map(\.url) == loose)
    }
}
