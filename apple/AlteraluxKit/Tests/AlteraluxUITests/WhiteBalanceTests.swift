import AlteraluxKit
import CoreGraphics
import Foundation
import Testing
@testable import AlteraluxUI

/// A small camera RAW: a gray card on the left, a warm ramp on the right. Its camera recorded a
/// neutral white balance, about 6500 K. `TestDNG`, in the tests of AlteraluxKit, writes it.
private let rawFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxUITests
    .deletingLastPathComponent() // Tests
    .appendingPathComponent("Fixtures/gray-card.dng")

/// Copies of the test RAW in a new temporary folder. The caller removes the folder.
@MainActor
private func writeTestRaws(count: Int) throws -> [URL] {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return try (1 ... count).map { index in
        let url = folder.appendingPathComponent("Raw \(index).dng")
        try FileManager.default.copyItem(at: rawFixture, to: url)
        return url
    }
}

/// The white balance of the selected photo, from the inspector to the preview.
@MainActor
struct WhiteBalanceTests {
    private func startedModel() async -> AppModel {
        let model = AppModel(dataDirectory: WindowedTests.engineData)
        await model.start()
        return model
    }

    /// How much bluer than red the gray card of the developed preview is.
    private func blueOverRed(of model: AppModel) throws -> Double {
        try blueOverRed(of: #require(model.preview?.cgImage))
    }

    /// How much bluer than red the gray card in the left half of `image` is.
    private func blueOverRed(of image: CGImage) throws -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                ),
            )
            // The middle of the left half, drawn over the one pixel.
            let width = CGFloat(image.width), height = CGFloat(image.height)
            context.draw(image, in: CGRect(x: -width / 4, y: -height / 2, width: width, height: height))
        }
        return Double(pixel[2]) / Double(max(pixel[0], 1))
    }

    private func wait(_ what: String, until condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while try !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aRawStartsFromWhatTheCameraRecorded() async throws {
        let raws = try writeTestRaws(count: 1)
        defer { try? FileManager.default.removeItem(at: raws[0].deletingLastPathComponent()) }
        let model = await startedModel()
        #expect(!model.canAdjustWhiteBalance && !model.whiteBalanceIsFixed)

        model.open(raws)
        try await wait("the preview") { model.preview != nil }
        #expect(model.alertMessage == nil)
        #expect(model.canAdjustWhiteBalance && !model.whiteBalanceIsFixed)
        #expect(abs(model.temperature - 6500) < 100)
        #expect(model.temperatureRange.contains(model.temperature))
        // Nothing is chosen: the settings say "as shot".
        #expect(model.settings.temperature == nil && model.settings.tint == nil)
    }

    @Test func choosingATemperatureDevelopsThePhotoAgain() async throws {
        let raws = try writeTestRaws(count: 1)
        defer { try? FileManager.default.removeItem(at: raws[0].deletingLastPathComponent()) }
        let model = await startedModel()
        model.open(raws)
        try await wait("the preview") { model.preview != nil }
        let asShot = try blueOverRed(of: model)

        // The light called warmer than it was: the photo turns cooler.
        model.temperature = 4000
        #expect(model.settings.temperature == 4000)
        model.settingsDidChange()
        try await wait("a cooler preview") { try blueOverRed(of: model) > asShot * 1.3 }

        model.tint += 30
        #expect(model.settings.tint != nil)
        model.settingsDidChange()
        // Back to the camera's values with the reset, and to its colors.
        model.resetAdjustments()
        #expect(model.settings.temperature == nil && model.settings.tint == nil)
        model.settingsDidChange()
        try await wait("the colors as shot") { try abs(blueOverRed(of: model) - asShot) < asShot * 0.05 }
        #expect(model.alertMessage == nil)
    }

    @Test func theAutomaticWhiteBalanceShowsInTheSlidersAndLeavesWhenOneMoves() async throws {
        let raws = try writeTestRaws(count: 1)
        defer { try? FileManager.default.removeItem(at: raws[0].deletingLastPathComponent()) }
        let model = await startedModel()
        model.open(raws)
        try await wait("the preview") { model.preview != nil }
        let asShot = try #require(model.asShotWhiteBalance)

        // The warm ramp of the test RAW reads as a warm light, far from the camera's daylight.
        model.isWhiteBalanceAutomatic = true
        model.settingsDidChange()
        try await wait("the measured white balance") { model.automaticWhiteBalance != nil }
        let automatic = try #require(model.automaticWhiteBalance)
        #expect(automatic.temperature < asShot.temperature - 300, "automatic: \(automatic)")
        #expect(model.temperature == automatic.temperature && model.tint == automatic.tint)
        #expect(model.settings.temperature == nil && model.settings.autoWhiteBalance)

        // Moving the tint chooses by hand from where the automatic one stood.
        model.tint = automatic.tint + 10
        #expect(!model.settings.autoWhiteBalance)
        #expect(model.temperature == automatic.temperature && model.tint == automatic.tint + 10)

        // Turned on again, it lets go of the hand's choice; turned off, what it gave stays, as
        // chosen by hand: the photo does not change until a slider moves.
        model.isWhiteBalanceAutomatic = true
        #expect(model.settings.temperature == nil && model.settings.tint == nil)
        model.isWhiteBalanceAutomatic = false
        #expect(!model.settings.autoWhiteBalance)
        #expect(model.temperature == automatic.temperature && model.tint == automatic.tint)
        #expect(model.settings.temperature == automatic.temperature)
        // Reset goes back to the camera's.
        model.reset(.shot)
        #expect(model.temperature == asShot.temperature && model.tint == asShot.tint)
        #expect(model.alertMessage == nil)
    }

    @Test func theTestRawHasNoLensToCorrect() async throws {
        let raws = try writeTestRaws(count: 1)
        defer { try? FileManager.default.removeItem(at: raws[0].deletingLastPathComponent()) }
        let model = await startedModel()
        model.open(raws)
        try await wait("the preview") { model.preview != nil }
        #expect(!model.correctsLens && !model.isLensCorrected)
    }

    @Test func theExportedFileHasTheWhiteBalanceChosen() async throws {
        let raws = try writeTestRaws(count: 1)
        let folder = raws[0].deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = await startedModel()
        model.open(raws)
        try await wait("the preview") { model.preview != nil }
        model.exportOptions.format = .png

        let asShotFile = folder.appendingPathComponent("as shot.png")
        await model.export(to: asShotFile)
        model.temperature = 4000
        model.settingsDidChange()
        let coolerFile = folder.appendingPathComponent("cooler.png")
        await model.export(to: coolerFile)
        #expect(model.alertMessage == nil)

        let asShot = try #require(ImageLoader.originalPreview(of: asShotFile, maxDimension: 240))
        let cooler = try #require(ImageLoader.originalPreview(of: coolerFile, maxDimension: 240))
        // The whole photo, not a preview of it.
        #expect(asShot.width == 240 && asShot.height == 160)
        #expect(try blueOverRed(of: cooler) > blueOverRed(of: asShot) * 1.3)
    }

    /// The slider stops at the camera's value, and there the settings say "as shot", so they
    /// mean the same on another photo.
    @Test func aValueBesideTheCamerasIsTheCameras() async throws {
        let raws = try writeTestRaws(count: 1)
        defer { try? FileManager.default.removeItem(at: raws[0].deletingLastPathComponent()) }
        let model = await startedModel()
        model.open(raws)
        try await wait("the preview") { model.preview != nil }
        let asShot = try #require(model.asShotWhiteBalance)

        model.temperature = asShot.temperature + 60
        #expect(model.settings.temperature == asShot.temperature + 60)
        model.temperature = asShot.temperature + 20
        #expect(model.settings.temperature == nil)
        #expect(model.temperature == asShot.temperature)

        model.tint = asShot.tint + 2
        #expect(model.settings.tint == asShot.tint + 2)
        model.tint = asShot.tint + 0.3
        #expect(model.settings.tint == nil)
    }

    @Test func eachPhotoKeepsItsWhiteBalance() async throws {
        let raws = try writeTestRaws(count: 2)
        defer { try? FileManager.default.removeItem(at: raws[0].deletingLastPathComponent()) }
        let model = await startedModel()
        model.open([raws[0]])
        try await wait("the preview") { model.preview != nil }
        model.temperature = 4000
        model.settingsDidChange()

        // A photo opened beside it starts from its own camera's values.
        model.open([raws[1]])
        #expect(model.settings.temperature == nil)
        try await wait("the second preview") { model.preview != nil }
        #expect(abs(model.temperature - 6500) < 100)

        model.selectAdjacent(offset: -1)
        #expect(model.settings.temperature == 4000)
        try await wait("the first preview") { model.preview != nil }
        #expect(model.temperature == 4000)
        #expect(model.alertMessage == nil)
    }

    @Test func aPhotoThatIsNotARawHasAFixedWhiteBalance() async throws {
        let pictures = try WindowedTests.writeTestPictures(count: 1)
        defer { try? FileManager.default.removeItem(at: pictures[0].deletingLastPathComponent()) }
        let model = await startedModel()
        model.open(pictures)
        try await wait("the preview") { model.preview != nil }
        #expect(!model.canAdjustWhiteBalance)
        #expect(model.whiteBalanceIsFixed)
        #expect(model.asShotWhiteBalance == nil)
    }
}

/// What the model keeps of the selected photo, decoded.
@MainActor
struct PhotoSourcesTests {
    private func sources() throws -> (PhotoSources, URL) {
        let raws = try writeTestRaws(count: 1)
        return try (PhotoSources(decoder: PhotoDecoder(url: raws[0])), raws[0].deletingLastPathComponent())
    }

    @Test func aSizeIsDecodedOnce() async throws {
        let (sources, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = DevelopSettings()
        let first = try await sources.source(dimension: 120, settings: settings)
        #expect(first.width == 120)
        let again = try await sources.source(dimension: 120, settings: settings)
        #expect(again.source === first.source)
        // Other settings do not change what is decoded.
        var brighter = settings
        brighter.exposureEV = 1
        #expect(try await sources.source(dimension: 120, settings: brighter).source === first.source)
    }

    @Test func anythingNotSmallerThanThePhotoIsTheWholeOfIt() async throws {
        let (sources, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(sources.longSide(framedBy: nil) == 240)
        let whole = try await sources.source(dimension: 0, settings: DevelopSettings())
        #expect(whole.width == 240 && whole.height == 160)
        #expect(try await sources.source(dimension: 240, settings: DevelopSettings()).source === whole.source)
        #expect(try await sources.source(dimension: 4096, settings: DevelopSettings()).source === whole.source)
    }

    @Test func anotherWhiteBalanceDecodesAgain() async throws {
        let (sources, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = DevelopSettings()
        let asShot = try await sources.source(dimension: 120, settings: settings)
        settings.temperature = 4000
        let cooler = try await sources.source(dimension: 120, settings: settings)
        #expect(cooler.source !== asShot.source)
        #expect(try await sources.source(dimension: 120, settings: settings).source === cooler.source)
        // What was decoded for the other white balance is not kept.
        settings.temperature = nil
        #expect(try await sources.source(dimension: 120, settings: settings).source !== asShot.source)
    }

    /// The scene's highlights and shadows are in the pixels, measured from the exposure: once
    /// they are changed, another exposure decodes again; while they are not, it does not. The
    /// meter's exposure is in the pixels whenever the exposure is automatic (ADR 0022).
    @Test func theScenesLightDecodesAgainAndThenSoDoesTheExposure() async throws {
        let (sources, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = DevelopSettings()
        let plain = try await sources.source(dimension: 120, settings: settings)
        #expect(plain.isMetered)
        settings.exposureEV = 0.5
        #expect(try await sources.source(dimension: 120, settings: settings).source === plain.source)
        settings.sceneTone.shadows = 0.5
        let lifted = try await sources.source(dimension: 120, settings: settings)
        #expect(lifted.source !== plain.source && lifted.isMetered)
        #expect(try await sources.source(dimension: 120, settings: settings).source === lifted.source)
        settings.exposureEV = 1
        let exposed = try await sources.source(dimension: 120, settings: settings)
        #expect(exposed.source !== lifted.source)
        // Anything else leaves what was decoded.
        settings.grainEnabled = false
        #expect(try await sources.source(dimension: 120, settings: settings).source === exposed.source)
        // With the meter off the pixels keep their own exposure.
        settings.autoExposure = false
        #expect(try await !sources.source(dimension: 120, settings: settings).isMetered)
    }

    @Test func onlyAFewReducedSizesAreKept() async throws {
        let (sources, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = DevelopSettings()
        let whole = try await sources.source(dimension: 0, settings: settings)
        let first = try await sources.source(dimension: 60, settings: settings)
        var last = first
        for dimension in [80, 100, 120] {
            last = try await sources.source(dimension: dimension, settings: settings)
        }
        #expect(try await sources.source(dimension: 120, settings: settings).source === last.source)
        #expect(try await sources.source(dimension: 60, settings: settings).source !== first.source)
        // The whole photo is kept beside them.
        #expect(try await sources.source(dimension: 0, settings: settings).source === whole.source)
    }

    @Test func twoRequestsForTheSameSizeShareOneDecode() async throws {
        let (sources, folder) = try sources()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = DevelopSettings()
        async let one = sources.source(dimension: 100, settings: settings)
        async let other = sources.source(dimension: 100, settings: settings)
        let (first, second) = try await (one, other)
        #expect(first.source === second.source)
    }
}
