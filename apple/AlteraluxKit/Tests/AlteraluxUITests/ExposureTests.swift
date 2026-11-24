import AlteraluxKit
import CoreGraphics
import Foundation
import Testing
@testable import AlteraluxUI

/// The exposure of the selected photo: left to the meter, or the hand's (ADR 0020).
@MainActor
struct ExposureTests {
    private func wait(_ what: String, until condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while try !condition() {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for \(what).")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// The mean of the developed preview, in 8-bit sRGB levels.
    private func brightness(of model: AppModel) throws -> Double {
        let image = try #require(model.preview?.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                ),
            )
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Double(bytes.reduce(0) { $0 + Int($1) }) / Double(bytes.count)
    }

    /// Changes the adjustments as a control does and waits for the preview developed with them:
    /// a new picture, not the one that was on screen before the change.
    private func change(_ model: AppModel, _ edit: (AppModel) -> Void) async throws {
        let before = model.preview?.cgImage
        edit(model)
        model.settingsDidChange()
        model.settleChange()
        try await wait("the preview of the change") { model.preview?.cgImage !== before && !model.isRendering }
    }

    /// Turning the meter off hands the exposure over where the meter left it: the slider reads
    /// what the meter chose with its compensation, and the photo is as bright as it was.
    /// Turning it on again starts from no compensation.
    @Test func theExposureStartsFromWhereTheMeterLeftIt() async throws {
        let pictures = try WindowedTests.writeTestPictures(count: 1)
        defer { try? FileManager.default.removeItem(at: pictures[0].deletingLastPathComponent()) }
        let model = AppModel(
            dataDirectory: WindowedTests.engineData,
            editsDirectory: pictures[0].deletingLastPathComponent().appendingPathComponent("edits"),
        )
        await model.start()
        model.open(pictures)
        try await wait("the preview") { model.preview != nil }
        #expect(model.isExposureAutomatic)

        try await change(model) { $0.settings.exposureEV = 0.5 }
        try await wait("the meter's reading") { model.meteredExposure != nil }
        let metered = try #require(model.meteredExposure)
        #expect(abs(metered) > 0.2, "The test picture is not at middle gray: the meter read \(metered).")
        let automatic = try brightness(of: model)

        try await change(model) { $0.isExposureAutomatic = false }
        #expect(!model.settings.autoExposure)
        #expect(abs(model.settings.exposureEV - (metered + 0.5)) <= 0.05 + 1e-9)
        // To the tenth of a stop the slider moves by.
        let byHand = try brightness(of: model)
        #expect(abs(byHand - automatic) < 4, "\(automatic) became \(byHand)")

        try await change(model) { $0.isExposureAutomatic = true }
        #expect(model.settings.autoExposure && model.settings.exposureEV == 0)
        #expect(model.alertMessage == nil)
    }

    /// Before the meter was read there is nothing to start from: the switch still turns.
    @Test func withoutAReadingTheSwitchStillTurns() async {
        let model = AppModel(dataDirectory: WindowedTests.engineData)
        await model.start()
        model.settings.exposureEV = 0.3
        model.isExposureAutomatic = false
        #expect(!model.settings.autoExposure && model.settings.exposureEV == 0.3)
        model.isExposureAutomatic = true
        #expect(model.settings.autoExposure && model.settings.exposureEV == 0)
    }
}
