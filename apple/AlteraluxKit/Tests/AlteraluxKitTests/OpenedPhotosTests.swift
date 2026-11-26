import Foundation
import Testing
@testable import AlteraluxKit

/// The photos opened on their own, remembered between launches.
struct OpenedPhotosTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-opened-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func photosOpenedAreRememberedByTheNextLaunchInTheirOrder() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = try ["B.jpg", "A.jpg", "C.jpg"].map { name in
            let photo = root.appendingPathComponent(name)
            try Data("x".utf8).write(to: photo)
            return photo
        }
        let store = root.appendingPathComponent("support/opened-photos.plist")

        let first = OpenedPhotos(storeURL: store)
        #expect(await first.load().isEmpty)
        #expect(await first.add([photos[0], photos[1]]) == [photos[0], photos[1]])
        // A photo opened again keeps its place.
        #expect(await first.add([photos[1], photos[2], photos[2]]) == photos)

        let next = OpenedPhotos(storeURL: store)
        #expect(await next.load().map(\.standardizedFileURL) == photos.map(\.standardizedFileURL))

        // Forgotten, or gone from the disk: not given back.
        #expect(await next.remove([photos[0]]).map(\.lastPathComponent) == ["A.jpg", "C.jpg"])
        try FileManager.default.removeItem(at: photos[2])
        let later = OpenedPhotos(storeURL: store)
        #expect(await later.load().map(\.lastPathComponent) == ["A.jpg"])
    }
}
