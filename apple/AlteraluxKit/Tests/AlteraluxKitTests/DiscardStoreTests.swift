import Foundation
import Testing
@testable import AlteraluxKit

/// The "discarded" mark of a photo, kept where it follows the photo.
struct DiscardStoreTests {
    /// A folder for one test, with a file standing in for a photo.
    private struct Fixture {
        let folder: URL
        let photo: URL
        let store: DiscardStore

        init() throws {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            photo = folder.appendingPathComponent("photo.tif")
            try Data("pixels".utf8).write(to: photo)
            store = DiscardStore(fallbackDirectory: folder.appendingPathComponent("marks"))
        }

        func remove() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: photo.path)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test func aPhotoIsMarkedInItselfAndTheMarkFollowsIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        #expect(!store.isDiscarded(photo))
        let modified = try photo.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        try store.setDiscarded(true, for: photo)
        #expect(store.isDiscarded(photo))
        // The file is the one it was, and nothing of the app's own is written.
        #expect(try Data(contentsOf: photo) == Data("pixels".utf8))
        let after = try URL(fileURLWithPath: photo.path)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(after == modified)
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("marks").path))

        let moved = fixture.folder.appendingPathComponent("moved.tif")
        try FileManager.default.moveItem(at: photo, to: moved)
        #expect(store.isDiscarded(moved) && !store.isDiscarded(photo))

        try store.setDiscarded(false, for: moved)
        #expect(!store.isDiscarded(moved))
        // Taking away a mark that is not there changes nothing.
        try store.setDiscarded(false, for: moved)
    }

    @Test func aPhotoThatCannotBeWrittenIsMarkedInTheAppsFolder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: photo.path)

        try store.setDiscarded(true, for: photo)
        #expect(store.isDiscarded(photo))
        #expect(FileManager.default.fileExists(atPath: store.fallbackFile(for: photo).path))
        try store.setDiscarded(false, for: photo)
        #expect(!store.isDiscarded(photo))
    }
}
