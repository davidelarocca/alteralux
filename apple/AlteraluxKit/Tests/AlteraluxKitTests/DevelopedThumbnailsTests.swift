import CoreGraphics
import Foundation
import Testing
@testable import AlteraluxKit

/// The upstream data folder, straight from the git submodule.
private let engineData = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxKitTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // AlteraluxKit
    .deletingLastPathComponent() // apple
    .deletingLastPathComponent() // repository root
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

/// A RAW of a gray card, small.
private let grayCard = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/gray-card.dng")

/// The photos of the grid and the strip developed small with their adjustments.
struct DevelopedThumbnailsTests {
    private struct Fixture {
        let folder: URL
        let photo: URL
        let cache: URL
        let renderer: FilmRenderer

        init() throws {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("alteralux-developed-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            photo = folder.appendingPathComponent("card.dng")
            try FileManager.default.copyItem(at: grayCard, to: photo)
            cache = folder.appendingPathComponent("cache")
            renderer = try FilmRenderer(dataDirectory: engineData)
        }

        func request(_ settings: DevelopSettings, side: Int = 128) -> DevelopedThumbnails.Request {
            DevelopedThumbnails.Request(photo: photo, settings: settings, maxDimension: side)
        }

        func remove() {
            try? FileManager.default.removeItem(at: folder)
        }

        /// Waits for the thumbnail written in the background.
        func waitForFiles(_ count: Int) async throws {
            let deadline = ContinuousClock.now + .seconds(30)
            while (try? FileManager.default.contentsOfDirectory(atPath: cache.path).count { $0.hasSuffix(".jpg") }) ?? 0 < count {
                try #require(ContinuousClock.now < deadline, "Waited 30 seconds for the thumbnails on disk.")
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    @Test func aPhotoIsDevelopedOnceForTheSameAdjustments() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let thumbnails = DevelopedThumbnails(cacheDirectory: fixture.cache)
        let request = fixture.request(DevelopSettings())
        #expect(await thumbnails.kept(request) == nil)

        let image = try #require(await thumbnails.thumbnail(request, renderer: fixture.renderer))
        #expect(max(image.width, image.height) <= 128)
        #expect(await thumbnails.thumbnail(request, renderer: fixture.renderer) != nil)
        #expect(await thumbnails.kept(request) != nil)
        #expect(await thumbnails.developedCount == 1)

        // Other adjustments are another thumbnail.
        _ = try #require(await thumbnails.thumbnail(fixture.request(DevelopSettings(exposureEV: 1)), renderer: fixture.renderer))
        #expect(await thumbnails.developedCount == 2)
    }

    @Test func theThumbnailsOnDiskServeTheNextLaunchUntilThePhotoChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let request = fixture.request(DevelopSettings())
        let first = DevelopedThumbnails(cacheDirectory: fixture.cache)
        _ = try #require(await first.thumbnail(request, renderer: fixture.renderer))
        try await fixture.waitForFiles(1)

        let next = DevelopedThumbnails(cacheDirectory: fixture.cache)
        #expect(await next.kept(request) != nil)
        #expect(await next.developedCount == 0)

        // The file rewritten: what was kept was made from another photo.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: fixture.photo.path,
        )
        let later = DevelopedThumbnails(cacheDirectory: fixture.cache)
        #expect(await later.kept(request) == nil)
        _ = try #require(await later.thumbnail(request, renderer: fixture.renderer))
        #expect(await later.developedCount == 1)
    }

    @Test func aRequestCancelledBeforeItsTurnDevelopsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let thumbnails = DevelopedThumbnails(cacheDirectory: nil, concurrency: 1)
        let task = Task { await thumbnails.thumbnail(fixture.request(DevelopSettings()), renderer: fixture.renderer) }
        task.cancel()
        #expect(await task.value == nil)
        #expect(await thumbnails.developedCount == 0)
    }
}
