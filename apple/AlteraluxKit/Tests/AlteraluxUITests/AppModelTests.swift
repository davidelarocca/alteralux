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

        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        try await waitForPreview(of: model, longSide: 1024)
        try await waitForPreview(of: model, longSide: 2048)
        #expect(model.alertMessage == nil)
    }

    /// A full-resolution render takes a second or more on a large photo: when the settings
    /// settle, the standard preview is shown first.
    @Test func aPhotoShownAtFullResolutionSettlesThroughTheStandardPreview() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 2400, height: 1600).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([photo])
        try await waitForPreview(of: model, longSide: 2048)
        // The viewer shows the photo at 100%: more pixels than the standard preview has.
        model.viewerDidChange(scale: 1)
        try await waitForPreview(of: model, longSide: 2400)

        model.settings.exposureEV = 0.5
        model.settingsDidChange()
        try await waitForPreview(of: model, longSide: 1024)
        try await waitForPreview(of: model, longSide: 2048)
        try await waitForPreview(of: model, longSide: 2400)
        #expect(model.alertMessage == nil)
    }

    private func waitForPreview(of model: AppModel, longSide: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while model.preview.map({ max($0.width, $0.height) }) != longSide {
            try #require(ContinuousClock.now < deadline, "No preview of \(longSide) px in 60 seconds.")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
