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
