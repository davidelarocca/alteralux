import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import SpektrafilmUI

extension WindowedTests {
    /// Saves images of the main window for review (`.build/swift-harness/screenshots/`), at the
    /// sizes of its row in docs/LAYOUT_CONTRACT.md. Nothing is compared with a baseline.
    @MainActor
    struct MainWindowScreenshots {
        private func startedModel() async -> AppModel {
            let model = AppModel(dataDirectory: WindowedTests.engineData)
            await model.start()
            return model
        }

        @Test func noPhoto() async {
            let model = await startedModel()
            #expect(Screenshot.capture("MainWindow", state: "no-photo") { MainWindow().environment(model) } == [])
        }

        @Test func developedPhoto() async throws {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("spektrafilm-screenshots-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let photo = folder.appendingPathComponent("Test picture.png")
            let picture = try #require(WindowedTests.testPicture(width: 1200, height: 800))
            let destination = try #require(
                CGImageDestinationCreateWithURL(photo as CFURL, UTType.png.identifier as CFString, 1, nil),
            )
            CGImageDestinationAddImage(destination, picture, nil)
            try #require(CGImageDestinationFinalize(destination))

            let model = await startedModel()
            model.open([photo])
            // Decoding and developing run off the main actor: wait for the developed photo and
            // its thumbnail, so the image shows what the user sees.
            let deadline = ContinuousClock.now + .seconds(30)
            while model.preview == nil || model.isRendering || model.photos.first?.thumbnail == nil {
                try #require(ContinuousClock.now < deadline, "The photo was not developed in 30 seconds.")
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(model.alertMessage == nil)
            #expect(Screenshot.capture("MainWindow", state: "photo") { MainWindow().environment(model) } == [])
        }
    }
}
