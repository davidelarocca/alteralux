import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// A photo with adjustments, shown developed with them in the library's grid and in the strip.
@MainActor
struct DevelopedLookTests {
    /// A folder "Shoot" of four test pictures, in a folder of its own.
    private func folderOfPictures() throws -> URL {
        let pictures = try WindowedTests.writeTestPictures(count: 4)
        let root = pictures[0].deletingLastPathComponent()
        let shoot = root.appendingPathComponent("Shoot")
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        for picture in pictures {
            try FileManager.default.moveItem(at: picture, to: shoot.appendingPathComponent(picture.lastPathComponent))
        }
        return root
    }

    /// A model as a launch of the app gives it, keeping what it remembers in `root`.
    private func launch(_ root: URL) -> AppModel {
        AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: root.appendingPathComponent("support"))
    }

    private func wait(_ what: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aPhotoWithAdjustmentsIsShownDevelopedInTheGridAndTheStrip() async throws {
        let root = try folderOfPictures()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = launch(root)
        await model.start()
        await model.addFolder(root.appendingPathComponent("Shoot"))
        let photos = model.library.photos
        model.develop(photos[1])
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        model.showLibrary()
        try await wait("the adjustments in the grid") { model.library.looks[photos[1]]?.exposureEV == 0.5 }
        let look = try #require(model.library.looks[photos[1]])
        #expect(model.library.looks.count == 1)

        // A tile of the grid asks for the photo developed with them, and gets it kept.
        let tile = DevelopedThumbnails.Request(photo: photos[1], settings: look, maxDimension: 320)
        #expect(await model.developedThumbnail(tile) != nil)
        #expect(await model.keptDevelopedThumbnail(tile) != nil)

        // The next launch develops it for the strip as soon as the folder goes there.
        let next = launch(root)
        await next.start()
        next.develop(photos[0])
        let strip = DevelopedThumbnails.Request(photo: photos[1], settings: look, maxDimension: AppModel.thumbnailDimension)
        let deadline = ContinuousClock.now + .seconds(60)
        while await next.keptDevelopedThumbnail(strip) == nil {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for the strip's developed thumbnail.")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await wait("the strip's thumbnail") { next.photos[1].thumbnail != nil }
    }
}
