import AlteraluxKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxUI

/// The paper the app pairs with a film when the user chooses the film.
@MainActor
struct MaterialsTests {
    private func startedModel() async -> AppModel {
        let model = AppModel(dataDirectory: WindowedTests.engineData)
        await model.start()
        return model
    }

    @Test func aBlackAndWhiteNegativeGetsABlackAndWhitePaper() async throws {
        let model = await startedModel()
        let film = try #require(model.films.first { $0.isBlackAndWhite && !$0.isPositive })

        model.chooseFilm(film.id)

        #expect(!model.settings.scanFilm)
        #expect(model.selectedPaper?.isBlackAndWhite == true)
    }

    @Test func aColorFilmChosenAfterwardsGoesBackToItsPaper() async throws {
        let model = await startedModel()
        let blackAndWhite = try #require(model.films.first { $0.isBlackAndWhite && !$0.isPositive })
        let color = try #require(model.films.first { $0.id == "kodak_portra_400" })

        model.chooseFilm(blackAndWhite.id)
        model.chooseFilm(color.id)

        #expect(model.settings.paperID == color.targetPrint)
        #expect(model.selectedPaper?.isBlackAndWhite == false)
    }

    /// A black and white film or paper measured at several development times offers them; a
    /// time chosen goes back to the middle one when the material changes, and a color film
    /// offers none.
    @Test func developmentTimesAreOfferedForTheMaterialsMeasuredAtSeveral() async throws {
        let model = await startedModel()
        let film = try #require(model.films.first { $0.isBlackAndWhite && !$0.isPositive && $0.developmentTimesMin.count > 1 })
        model.chooseFilm(film.id)
        #expect(model.filmDevelopmentTimes == film.developmentTimesMin)

        model.settings.filmDevelopmentTime = film.developmentTimesMin.last
        model.settings.printDevelopmentTime = model.printDevelopmentTimes.last
        if let otherPaper = model.papers.first(where: { $0.isBlackAndWhite && $0.id != model.settings.paperID }) {
            model.choosePaper(otherPaper.id)
            #expect(model.settings.printDevelopmentTime == nil)
            #expect(model.settings.filmDevelopmentTime == film.developmentTimesMin.last)
        }
        model.chooseFilm("kodak_portra_400")
        #expect(model.settings.filmDevelopmentTime == nil && model.filmDevelopmentTimes.isEmpty)
    }

    /// The reason for the pairing: on the paper the app picks, a neutral gray stays neutral. On
    /// a color paper it came out orange (about 178, 124, 61 in sRGB).
    @Test func aGrayDevelopedOnBlackAndWhiteFilmStaysNeutral() async throws {
        let model = await startedModel()
        let film = try #require(model.films.first { $0.isBlackAndWhite && !$0.isPositive })
        model.chooseFilm(film.id)
        var settings = model.settings
        settings.grainEnabled = false

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alteralux-gray-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeGray(to: url)
        let renderer = try FilmRenderer(dataDirectory: WindowedTests.engineData, backend: .cpu)
        let developed = try await renderer.render(ImageLoader.load(url), settings: settings, quality: .full)

        let pixel = try meanColor(of: developed.cgImage)
        #expect(abs(pixel.red - pixel.blue) <= 3, "red and blue should match: \(pixel)")
        #expect(abs(pixel.red - pixel.green) <= 3, "red and green should match: \(pixel)")
    }

    private func writeGray(to url: URL) throws {
        let context = try #require(
            CGContext(
                data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ),
        )
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
        )
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    /// The image averaged into one sRGB pixel.
    private func meanColor(of image: CGImage) throws -> MeanColor {
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                ),
            )
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return MeanColor(red: Int(bytes[0]), green: Int(bytes[1]), blue: Int(bytes[2]))
    }
}

private struct MeanColor {
    let red: Int
    let green: Int
    let blue: Int
}
