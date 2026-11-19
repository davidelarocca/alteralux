import Foundation
import SpektrafilmKit
import Testing

@testable import SpektrafilmUI

/// The upstream data folder, straight from the git submodule.
private let dataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SpektrafilmUITests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // SpektrafilmKit
    .deletingLastPathComponent()  // apple
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

@MainActor
@Suite struct AppModelTests {
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

    @Test func zoomRequestsAreDistinctEvenWhenRepeated() {
        let model = AppModel(dataDirectory: dataDirectory)
        let first = model.zoomRequestID
        model.zoom(.actualSize)
        model.zoom(.actualSize)
        #expect(model.zoomRequestID == first + 2)
        #expect(model.zoomCommand == .actualSize)
    }
}
