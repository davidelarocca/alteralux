import Foundation
import Testing
@testable import AlteraluxKit

/// Keeping a photo's adjustments where they follow the photo.
struct EditStoreTests {
    /// A folder for one test, with a file standing in for a photo and a store that falls back
    /// to a folder inside it.
    private struct Fixture {
        let folder: URL
        let photo: URL
        let store: EditStore

        init() throws {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            photo = folder.appendingPathComponent("photo.tif")
            try Data("pixels".utf8).write(to: photo)
            store = EditStore(fallbackDirectory: folder.appendingPathComponent("edits"))
        }

        func remove() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: photo.path)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func edited() -> DevelopSettings {
        var settings = DevelopSettings()
        settings.filmID = "fujifilm_velvia_100"
        settings.scanFilm = true
        settings.exposureEV = 0.7
        settings.temperature = 4200
        return settings
    }

    @Test func adjustmentsAreKeptInThePhotoItself() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (folder, photo, store) = (fixture.folder, fixture.photo, fixture.store)
        #expect(store.load(for: photo) == nil)
        let modified = try photo.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        #expect(try await store.save(edited(), for: photo) == .photo)
        #expect(store.load(for: photo) == edited())
        // The photo is the same file as before: its pixels and its date.
        #expect(try Data(contentsOf: photo) == Data("pixels".utf8))
        let after = try URL(fileURLWithPath: photo.path)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(after == modified)
        // Nothing of the app's own is written when the photo can carry its adjustments.
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("edits").path))

        // The latest adjustments replace the earlier ones.
        #expect(try await store.save(DevelopSettings(), for: photo) == .photo)
        #expect(store.load(for: photo) == DevelopSettings())
    }

    @Test func adjustmentsFollowThePhotoWhenItIsMovedOrCopied() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (folder, photo, store) = (fixture.folder, fixture.photo, fixture.store)
        try await store.save(edited(), for: photo)

        let copy = folder.appendingPathComponent("copy.tif")
        try FileManager.default.copyItem(at: photo, to: copy)
        let moved = folder.appendingPathComponent("moved and renamed.tif")
        try FileManager.default.moveItem(at: photo, to: moved)
        #expect(store.load(for: copy) == edited())
        #expect(store.load(for: moved) == edited())
        #expect(store.load(for: photo) == nil)
    }

    /// A read-only disk, a locked card: the adjustments are kept in the app's folder, and move
    /// into the photo the first time it can be written.
    @Test func aPhotoThatCannotBeWrittenKeepsItsAdjustmentsInTheAppsFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: photo.path)
        #expect(try await store.save(edited(), for: photo) == .store)
        #expect(store.load(for: photo) == edited())
        #expect(FileManager.default.fileExists(atPath: store.fallbackFile(for: photo).path))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: photo.path)
        var later = edited()
        later.exposureEV = -1
        #expect(try await store.save(later, for: photo) == .photo)
        #expect(store.load(for: photo) == later)
        #expect(!FileManager.default.fileExists(atPath: store.fallbackFile(for: photo).path))
    }

    /// This version cannot read it, so it must not replace it: its own adjustments go to the
    /// app's folder, and the photo keeps what the later version wrote.
    @Test func aPhotoEditedByALaterVersionIsLeftAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        let later = Data(#"{"version":99,"settings":{"filmID":"a_film_of_the_future"}}"#.utf8)
        let written = later.withUnsafeBytes {
            setxattr(photo.path, EditStore.attributeName, $0.baseAddress, later.count, 0, 0)
        }
        #expect(written == 0)
        #expect(store.load(for: photo) == nil)

        #expect(try await store.save(edited(), for: photo) == .store)
        #expect(store.load(for: photo) == edited())
        var carried = Data(count: later.count)
        let read = carried.withUnsafeMutableBytes {
            getxattr(photo.path, EditStore.attributeName, $0.baseAddress, later.count, 0, 0)
        }
        #expect(read == later.count && carried == later)
    }

    @Test func removingForgetsWhatThePhotoCarries() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        try await store.save(edited(), for: photo)
        #expect(store.hasAdjustments(for: photo))

        try await store.remove(for: photo)
        #expect(store.load(for: photo) == nil)
        #expect(!store.hasAdjustments(for: photo))
        #expect(try Data(contentsOf: photo) == Data("pixels".utf8))
    }

    @Test func removingForgetsWhatTheAppsFolderKeeps() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: photo.path)
        #expect(try await store.save(edited(), for: photo) == .store)

        try await store.remove(for: photo)
        #expect(store.load(for: photo) == nil)
        #expect(!store.hasAdjustments(for: photo))
        #expect(!FileManager.default.fileExists(atPath: store.fallbackFile(for: photo).path))
    }

    @Test func removingWhereNothingIsKeptIsNotAnError() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        try await store.remove(for: photo)
        #expect(store.load(for: photo) == nil)
    }

    @Test func removingLeavesWhatALaterVersionWrote() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        let later = Data(#"{"version":99,"settings":{"filmID":"a_film_of_the_future"}}"#.utf8)
        let written = later.withUnsafeBytes {
            setxattr(photo.path, EditStore.attributeName, $0.baseAddress, later.count, 0, 0)
        }
        #expect(written == 0)

        try await store.remove(for: photo)
        var carried = Data(count: later.count)
        let read = carried.withUnsafeMutableBytes {
            getxattr(photo.path, EditStore.attributeName, $0.baseAddress, later.count, 0, 0)
        }
        #expect(read == later.count && carried == later)
    }

    @Test func removingFromAPhotoThatCannotBeWrittenFails() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        try await store.save(edited(), for: photo)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: photo.path)

        await #expect(throws: (any Error).self) { try await store.remove(for: photo) }
        #expect(store.load(for: photo) == edited())
    }

    /// What is in the attribute but is not adjustments at all is replaced.
    @Test func anAttributeThatIsNotAdjustmentsIsReplaced() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (photo, store) = (fixture.photo, fixture.store)
        let junk = Data("not json".utf8)
        _ = junk.withUnsafeBytes { setxattr(photo.path, EditStore.attributeName, $0.baseAddress, junk.count, 0, 0) }
        #expect(try await store.save(edited(), for: photo) == .photo)
        #expect(store.load(for: photo) == edited())
    }

    /// Settings saved before a parameter existed are read with its default.
    @Test func settingsSavedByAnEarlierVersionAreRead() throws {
        let saved = Data(#"{"filmID":"fujifilm_velvia_100","exposureEV":0.7}"#.utf8)
        let settings = try JSONDecoder().decode(DevelopSettings.self, from: saved)
        var expected = DevelopSettings()
        expected.filmID = "fujifilm_velvia_100"
        expected.exposureEV = 0.7
        #expect(settings == expected)
        #expect(try JSONDecoder().decode(DevelopSettings.self, from: Data("{}".utf8)) == DevelopSettings())
        // And what is saved now is read back whole.
        var edited = edited()
        edited.advancedJSON = #"{"camera":{"film_format_mm":60}}"#
        let roundTrip = try JSONDecoder().decode(DevelopSettings.self, from: JSONEncoder().encode(edited))
        #expect(roundTrip == edited)
    }
}
