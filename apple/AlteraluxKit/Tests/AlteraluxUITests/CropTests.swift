import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// Cropping the selected photo: the whole photo while the frame is chosen, the framed one once
/// it is kept, nothing changed when it is let go.
@MainActor
struct CropTests {
    private static let dataDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AlteraluxUITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // AlteraluxKit
        .deletingLastPathComponent() // apple
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

    @Test func aFrameKeptIsDevelopedAndOneLetGoChangesNothing() async throws {
        let photo = try #require(WindowedTests.writeTestPictures(count: 1, width: 2400, height: 1600).first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        let model = AppModel(dataDirectory: Self.dataDirectory)
        await model.start()
        model.open([photo])
        try await waitForPreview(of: model) { $0.width == 2048 }

        model.beginCrop()
        #expect(model.isCropping)
        #expect(!model.canCompare, "The original is not shown over the frame.")
        model.setCropAspect(.square)
        let session = try #require(model.cropSession)
        #expect(abs(session.crop.framedSize(of: session.photo).width - 1600) < 1)
        #expect(model.settings.crop == nil, "The frame is only chosen.")

        model.confirmCrop()
        #expect(!model.isCropping)
        let kept = try #require(model.settings.crop)
        #expect(kept == session.crop)
        // The framed picture is developed: the square of 1600 px, whole.
        try await waitForPreview(of: model) { $0.width == 1600 && $0.height == 1600 }
        #expect(model.previewCrop == kept)
        #expect(model.photoSize.map { abs($0.width - 1600) < 1 && abs($0.height - 1600) < 1 } == true)

        // Opened again, the photo is shown whole, and its frame is where it was left.
        model.beginCrop()
        #expect(model.cropSession?.crop == kept)
        try await waitForPreview(of: model) { $0.width == 2048 && $0.height < 2048 }
        model.cropAngle = 4
        model.cancelCrop()
        #expect(model.settings.crop == kept)
        try await waitForPreview(of: model) { $0.width == 1600 && $0.height == 1600 }
        #expect(model.alertMessage == nil)
    }

    /// Turning the photo shrinks the frame to stay inside it; turning it back gives it back.
    @Test func straighteningThereAndBackGivesTheFrameBack() {
        var session = CropSession(photo: CGSize(width: 3000, height: 2000), crop: nil)
        session.setAspect(.fourByFive)
        #expect(session.aspect.title(isUpright: session.isUpright) == "5:4")
        let start = session.crop
        session.angle = 12
        #expect(session.crop.width < start.width && session.crop.fits(in: session.photo))
        session.angle = 0
        #expect(session.crop == start)
        session.setUpright(true)
        let size = session.crop.framedSize(of: session.photo)
        #expect(abs(size.width / size.height - 0.8) < 1e-6)
        // A quarter turn stands the frame upright; mirrored and turned back, it is as it was.
        let upright = session.crop
        session.turnLeft()
        #expect(!session.isUpright && session.aspect.title(isUpright: session.isUpright) == "5:4")
        session.flip()
        session.flip()
        session.turnLeft()
        session.turnLeft()
        session.turnLeft()
        let back = session.crop
        let edges = [back.left - upright.left, back.top - upright.top, back.width - upright.width, back.height - upright.height]
        #expect(edges.allSatisfy { abs($0) < 1e-9 } && back.quarterTurns == 0 && !back.isFlipped && session.isUpright)
        session.reset()
        #expect(session.result == nil && session.aspect == .freeform)
    }

    private func waitForPreview(of model: AppModel, until isWanted: (DevelopedImage) -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !(model.preview.map(isWanted) ?? false) {
            try #require(ContinuousClock.now < deadline, "No such preview in 60 seconds.")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
