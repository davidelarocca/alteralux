import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// The upstream data folder, straight from the git submodule.
private let dataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxUITests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // AlteraluxKit
    .deletingLastPathComponent() // apple
    .deletingLastPathComponent() // repository root
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

@MainActor
struct AppModelTests {
    private func startedModel() async -> AppModel {
        let model = AppModel(dataDirectory: dataDirectory)
        await model.start()
        return model
    }

    @Test func startLoadsTheCatalogue() async {
        let model = await startedModel()
        #expect(model.alertMessage == nil)
        #expect(!model.isStarting)
        #expect(model.films.contains { $0.id == DevelopSettings().filmID })
        #expect(model.papers.contains { $0.id == DevelopSettings().paperID })
    }

    @Test func aMissingDataFolderIsReported() async {
        let model = AppModel(dataDirectory: URL(fileURLWithPath: "/nonexistent/data"))
        await model.start()
        #expect(model.alertMessage != nil)
        #expect(model.films.isEmpty)
    }

    /// A file offered as a folder is refused with the reason, not a bare "could not be added".
    @Test func aFolderThatCannotBeAddedSaysWhy() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-add-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("photo.jpg")
        try Data("pixels".utf8).write(to: file)
        let model = AppModel(dataDirectory: dataDirectory, editsDirectory: folder.appendingPathComponent("support"))

        await model.addFolder(file)

        let message = try #require(model.alertMessage)
        #expect(message.contains("photo.jpg"))
        #expect(message.contains(LibraryFoldersError.notAFolder(file).localizedDescription))
    }

    @Test func choosingASlideFilmScansItDirectly() async {
        let model = await startedModel()
        model.chooseFilm("fujifilm_velvia_100")
        #expect(model.settings.scanFilm)
        model.chooseFilm("kodak_portra_400")
        #expect(!model.settings.scanFilm)
    }

    @Test func choosingAFilmSelectsItsRecommendedPaper() async throws {
        let model = await startedModel()
        let film = try #require(model.films.first { $0.targetPrint != nil && $0.targetPrint != model.settings.paperID })
        model.chooseFilm(film.id)
        if model.papers.contains(where: { $0.id == film.targetPrint }) {
            #expect(model.settings.paperID == film.targetPrint)
        }
    }

    @Test func resetKeepsTheMaterials() async {
        let model = await startedModel()
        model.chooseFilm("fujifilm_velvia_100")
        model.settings.exposureEV = 1.5
        model.settings.grainEnabled = false
        model.resetAdjustments()
        #expect(model.settings.filmID == "fujifilm_velvia_100")
        #expect(model.settings.scanFilm)
        #expect(model.settings.exposureEV == 0)
        #expect(model.settings.grainEnabled)
    }

    @Test func exportNameUsesTheFilmAsTheUserReadsIt() {
        let source = URL(fileURLWithPath: "/photos/IMG_0042.CR3")
        #expect(
            AppModel.exportFileName(source: source, film: "Kodak Portra 400", format: .jpeg)
                == "IMG_0042 Kodak Portra 400.jpg",
        )
        #expect(
            AppModel.exportFileName(source: source, film: "Kodak Portra 800 (Push 1)", format: .tiff)
                == "IMG_0042 Kodak Portra 800 (Push 1).tif",
        )
        // Nothing in the name may read as a folder.
        #expect(
            AppModel.exportFileName(source: source, film: "A/B: C", format: .png) == "IMG_0042 A-B- C.png",
        )
    }

    @Test func commandsThatNeedAPhotoAreOffWithoutOne() throws {
        let model = AppModel(dataDirectory: dataDirectory)
        #expect(!model.canZoom)
        #expect(!model.canStepThroughPhotos)

        let files = try WindowedTests.writeTestPictures(count: 2)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        model.open([files[0]])
        #expect(!model.canStepThroughPhotos)
        model.open([files[1]])
        #expect(model.canStepThroughPhotos)
        model.removeSelection()
        #expect(!model.canStepThroughPhotos)
    }

    @Test func zoomRequestsAreDistinctEvenWhenRepeated() {
        let model = AppModel(dataDirectory: dataDirectory)
        let first = model.zoomRequestID
        model.zoom(.actualSize)
        model.zoom(.actualSize)
        #expect(model.zoomRequestID == first + 2)
        #expect(model.zoomCommand == .actualSize)
    }

    /// While the settings change the preview is the lighter one, so it keeps up with a moving
    /// control; the full one follows when they stay still.
    @Test func thePreviewIsLighterWhileTheSettingsChange() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 2400, height: 1600).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        try await waitForPreview(of: model, longSide: 2048)

        // The test says when the settings stand still: the lighter preview stays until it has
        // been seen, however slow the machine.
        model.settleDelay = .seconds(600)
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        try await waitForPreview(of: model, longSide: 1024)
        model.settleChange()
        try await waitForPreview(of: model, longSide: 2048)
        #expect(model.alertMessage == nil)
    }

    /// Nothing has to say the settings stand still: a moment without a change is enough.
    @Test func thePreviewTheViewerNeedsFollowsOnItsOwn() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 2400, height: 1600).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        try await waitForPreview(of: model, longSide: 2048)
        let before = model.preview?.cgImage

        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        let deadline = ContinuousClock.now + .seconds(60)
        while model.preview?.cgImage === before || model.preview.map({ max($0.width, $0.height) }) != 2048 {
            try #require(ContinuousClock.now < deadline, "No new preview of 2048 px in 60 seconds.")
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.alertMessage == nil)
    }

    /// In a large window the fitted photo is shown with more pixels than the standard preview
    /// has: the preview grows to what the viewer shows, not to the whole photo.
    @Test func thePreviewGrowsWithThePhotoOnScreen() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 3600, height: 2400).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        try await waitForPreview(of: model, longSide: 2048)
        // The viewer shows the photo 2880 pixels wide.
        model.viewerDidChange(ViewerZoom(scale: 0.8, fitScale: 0.8, isFitted: true))
        try await waitForPreview(of: model, longSide: 2560)

        // Quick enough to follow the lighter preview directly.
        model.settleDelay = .seconds(600)
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        try await waitForPreview(of: model, longSide: 1024)
        model.settleChange()
        #expect(try await previewSizes(of: model, until: 2560) == [1024, 2560])
        #expect(model.alertMessage == nil)
    }

    /// A render of the whole of a large photo takes a second or more: when the settings settle,
    /// the standard preview is shown first.
    @Test func aPhotoShownAtFullResolutionSettlesThroughTheStandardPreview() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 3600, height: 2400).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        try await waitForPreview(of: model, longSide: 2048)
        // The viewer shows the photo at 100%: every pixel of it.
        model.viewerDidChange(ViewerZoom(scale: 1, fitScale: 0.4, isFitted: false))
        try await waitForPreview(of: model, longSide: 3600)

        // Each preview stays until the test has seen it: the lighter one until the settings are
        // said to stand still, the standard one for a pause long enough for a slow machine.
        model.settleDelay = .seconds(600)
        model.slowPreviewDelay = .seconds(3)
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        try await waitForPreview(of: model, longSide: 1024)
        model.settleChange()
        try await waitForPreview(of: model, longSide: 2048)
        try await waitForPreview(of: model, longSide: 3600)
        #expect(model.alertMessage == nil)
    }

    /// A render cannot be interrupted, so one that takes long waits for the settings to stay
    /// still: a control taken up again after a short pause never finds it in the way.
    @Test func aSlowPreviewWaitsForTheSettingsToStayStill() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 3600, height: 2400).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        try await waitForPreview(of: model, longSide: 2048)
        model.viewerDidChange(ViewerZoom(scale: 1, fitScale: 0.4, isFitted: false))
        try await waitForPreview(of: model, longSide: 3600)

        // The pause is as long as the test needs, so a slow machine sees the same as a fast one.
        model.slowPreviewDelay = .seconds(30)
        model.settleDelay = .seconds(600)
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        model.settleChange()
        try await waitForPreview(of: model, longSide: 2048)
        // A short pause, then the control moves again.
        model.settings.exposureEV = 0.6
        model.settingsDidChange()
        try await waitForPreview(of: model, longSide: 1024)
        model.settleChange()
        #expect(try await previewSizes(of: model, until: 2048) == [1024, 2048])
        #expect(model.alertMessage == nil)
    }

    /// Once the settings have stayed still, the preview the viewer needs is rendered, however
    /// short the pause is.
    @Test func theSlowPreviewComesWhenThePauseEnds() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 3600, height: 2400).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        try await waitForPreview(of: model, longSide: 2048)
        model.viewerDidChange(ViewerZoom(scale: 1, fitScale: 0.4, isFitted: false))
        try await waitForPreview(of: model, longSide: 3600)

        // No pause at all: it ends before the standard preview is on screen.
        model.slowPreviewDelay = .zero
        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        model.settleChange()
        try await waitForPreview(of: model, longSide: 3600)
        #expect(model.alertMessage == nil)
    }

    /// A photo removed while it is still being opened does not come back into an empty strip.
    @Test func aPhotoRemovedWhileItOpensStaysRemoved() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 2400, height: 1600).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        model.removeSelection()
        #expect(model.photos.isEmpty)
        // Long enough for the photo to finish opening.
        try await Task.sleep(for: .seconds(1))
        #expect(model.photoSize == nil && model.preview == nil)
        #expect(!model.canExport && !model.canZoom)
    }

    /// The next photo starts fitted: it is not rendered whole because the last one was at 100%.
    @Test func aPhotoOpenedAfterAZoomedOneStartsFromTheStandardPreview() async throws {
        let photos = try WindowedTests.writeTestPictures(count: 2, width: 3600, height: 2400)
        defer { try? FileManager.default.removeItem(at: photos[0].deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photos[0]])
        try await waitForPreview(of: model, longSide: 2048)
        model.viewerDidChange(ViewerZoom(scale: 1, fitScale: 0.4, isFitted: false))
        try await waitForPreview(of: model, longSide: 3600)

        model.open([photos[1]])
        #expect(model.preview == nil)
        try await waitForPreview(of: model, longSide: 2048)
        #expect(model.alertMessage == nil)
    }

    private func waitForPreview(of model: AppModel, longSide: Int) async throws {
        _ = try await previewSizes(of: model, until: longSide)
    }

    /// The long sides of the previews the model shows, one after the other, until one of `longSide`.
    private func previewSizes(of model: AppModel, until longSide: Int) async throws -> [Int] {
        let deadline = ContinuousClock.now + .seconds(60)
        var sizes: [Int] = []
        while sizes.last != longSide {
            try #require(ContinuousClock.now < deadline, "No preview of \(longSide) px in 60 seconds.")
            if let size = model.preview.map({ max($0.width, $0.height) }), size != sizes.last {
                sizes.append(size)
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        return sizes
    }
}
