import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxUI

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
                .appendingPathComponent("alteralux-screenshots-\(UUID().uuidString)")
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

        /// The strip with what its thumbnails say of a photo: colored tags as dots, the mark
        /// of adjustments, the mark of a discarded photo.
        @Test func stripWithMarks() async throws {
            let pictures = try WindowedTests.writeTestPictures(count: 4)
            let folder = pictures[0].deletingLastPathComponent()
            defer { try? FileManager.default.removeItem(at: folder) }
            let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: folder.appendingPathComponent("support"))
            await model.start()
            await model.addFolder(folder)
            let photos = model.library.photos
            try #require(photos.count == 4)

            model.develop(photos[0])
            model.settings.exposureEV = 0.5
            model.settingsDidChange()
            model.toggleTag("Red", color: .red, on: [photos[1]])
            model.toggleTag("Blue", color: .blue, on: [photos[1]])
            model.toggleTag("Green", color: .green, on: [photos[2]])
            model.toggleDiscarded(model.photos[2])
            let deadline = ContinuousClock.now + .seconds(30)
            func isReady() -> Bool {
                model.preview != nil && !model.isRendering && model.photos.allSatisfy { $0.thumbnail != nil }
                    && model.photos[0].hasAdjustments && model.tags(of: model.photos[1]).count == 2
                    && !model.tags(of: model.photos[2]).isEmpty
            }
            while !isReady() {
                try #require(ContinuousClock.now < deadline, "The strip was not ready in 30 seconds.")
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(model.alertMessage == nil)
            #expect(Screenshot.capture("MainWindow", state: "strip-marks") { MainWindow().environment(model) } == [])
        }
    }
}

extension WindowedTests {
    /// Saves images of the library for review: photos of different shapes, tags, a selection
    /// with its bar of actions. Nothing is compared with a baseline.
    @MainActor
    struct LibraryScreenshots {
        @Test func photosOfDifferentShapesWithASelection() async throws {
            let wide = try WindowedTests.writeTestPictures(count: 5, width: 300, height: 200)
            let folder = wide[0].deletingLastPathComponent()
            defer { try? FileManager.default.removeItem(at: folder) }
            let upright = try WindowedTests.writeTestPictures(count: 3, width: 200, height: 300)
            defer { try? FileManager.default.removeItem(at: upright[0].deletingLastPathComponent()) }
            for (index, picture) in upright.enumerated() {
                try FileManager.default.moveItem(at: picture, to: folder.appendingPathComponent("Upright \(index + 1).png"))
            }
            let tags = try PropertyListSerialization.data(fromPropertyList: ["Trip\n2", "Print\n6"], format: .binary, options: 0)
            for picture in [wide[1], wide[3]] {
                _ = tags.withUnsafeBytes {
                    setxattr(picture.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, tags.count, 0, 0)
                }
            }

            let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: folder.appendingPathComponent("support"))
            await model.start()
            await model.addFolder(folder)
            let photos = model.library.photos
            #expect(photos.count == 8)
            model.library.click(photos[1])
            model.library.click(photos[6], toggling: true)
            // The thumbnails are made off the main actor: give them a moment to arrive.
            try await Task.sleep(for: .milliseconds(1500))
            #expect(Screenshot.capture("MainWindow", state: "library-selection") { MainWindow().environment(model) } == [])
        }
    }
}
