import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// Photos opened outside the library's folders: an entry of their own in the sidebar.
@MainActor
struct OpenedPhotosInTheLibraryTests {
    /// A folder for the library, photos outside it, and where a model keeps what it remembers.
    private struct Fixture {
        let root: URL
        let shoot: URL
        let loose: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
            shoot = root.appendingPathComponent("Shoot")
            loose = root.appendingPathComponent("Downloads")
            for folder in [shoot, loose] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            for name in ["IMG_1.jpg", "IMG_2.jpg"] {
                try Data("x".utf8).write(to: shoot.appendingPathComponent(name))
            }
            for name in ["b.jpg", "a.jpg"] {
                try Data("x".utf8).write(to: loose.appendingPathComponent(name))
            }
        }

        /// A model as a launch of the app gives it.
        @MainActor
        func model() -> LibraryModel {
            LibraryModel(
                storeURL: root.appendingPathComponent("support/folders.plist"), cacheDirectory: nil,
                discards: DiscardStore(fallbackDirectory: root.appendingPathComponent("support/discarded")),
                hasAdjustments: { _ in false },
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func names(_ photos: [URL]) -> [String] {
        photos.map(\.lastPathComponent)
    }

    @Test func photosOpenedOutsideTheFoldersHaveTheirOwnEntry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        try await model.add(fixture.shoot)
        #expect(model.opened.isEmpty)

        // A photo of a folder of the library is found there; the others get the entry.
        await model.noteOpened([
            fixture.shoot.appendingPathComponent("IMG_1.jpg"),
            fixture.loose.appendingPathComponent("b.jpg"), fixture.loose.appendingPathComponent("a.jpg"),
        ])
        #expect(names(model.opened) == ["b.jpg", "a.jpg"])
        #expect(model.place == .folder(fixture.shoot) && model.arrangesFiles)

        await model.selectOpened()
        #expect(model.place == .opened && model.selectedFolder == nil)
        // Their folder is not the app's: they are not moved, duplicated, renamed or trashed.
        #expect(!model.arrangesFiles)
        // In the grid by name, as a folder's photos are.
        #expect(names(model.visiblePhotos) == ["a.jpg", "b.jpg"])

        // Forgotten one by one: the files stay; with none left, the folder is shown again.
        await model.forgetOpened([fixture.loose.appendingPathComponent("a.jpg")])
        #expect(names(model.visiblePhotos) == ["b.jpg"])
        await model.forgetOpened(model.opened)
        #expect(model.opened.isEmpty && model.place == .folder(fixture.shoot))
        #expect(FileManager.default.fileExists(atPath: fixture.loose.appendingPathComponent("a.jpg").path))
    }

    @Test func theNextLaunchShowsThemWhenNoFolderWasAdded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.model()
        await first.load()
        #expect(first.isEmpty)
        await first.noteOpened([fixture.loose.appendingPathComponent("a.jpg")])
        #expect(!first.isEmpty)

        let next = fixture.model()
        await next.load()
        #expect(names(next.opened) == ["a.jpg"])
        #expect(next.place == .opened && names(next.photos) == ["a.jpg"])
    }

    @Test func aFolderAddedTakesThePhotosOpenedInIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.load()
        await model.noteOpened([fixture.loose.appendingPathComponent("a.jpg"), fixture.shoot.appendingPathComponent("IMG_2.jpg")])
        #expect(model.opened.count == 2)

        try await model.add(fixture.shoot)
        #expect(names(model.opened) == ["a.jpg"])
        #expect(model.place == .folder(fixture.shoot))
    }

    @Test func aPhotoOpenedInTheAppIsFoundAgainInTheLibrary() async throws {
        let pictures = try WindowedTests.writeTestPictures(count: 2)
        let root = pictures[0].deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: root.appendingPathComponent("support"))
        await model.start()
        #expect(!model.hasLibrary)

        model.open([pictures[1]])
        let deadline = ContinuousClock.now + .seconds(30)
        while model.library.opened.isEmpty {
            try #require(ContinuousClock.now < deadline, "Waited 30 seconds for the opened photo in the library.")
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.library.opened == [pictures[1]])
        // There is a library to go back to, and the photo is in it.
        #expect(model.hasLibrary)
        await model.library.selectOpened()
        model.develop(pictures[1])
        #expect(model.photos.map(\.url) == [pictures[1]] && model.selection?.url == pictures[1])
    }
}
