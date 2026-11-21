import CoreGraphics
import Foundation
import Testing
@testable import AlteraluxKit

/// The frame of a photo: kept inside the turned photo, held to a shape, and applied before the
/// engine (ADR 0010).
struct PhotoCropTests {
    private let photo = CGSize(width: 6000, height: 4000)

    private func pixelAspect(_ crop: PhotoCrop) -> Double {
        let size = crop.framedSize(of: photo)
        return size.width / size.height
    }

    @Test func theWholePhotoFitsUntilItIsTurned() {
        #expect(PhotoCrop.whole.isWhole)
        #expect(PhotoCrop.whole.fits(in: photo))
        var turned = PhotoCrop.whole
        turned.angle = 5
        #expect(!turned.isWhole)
        #expect(!turned.fits(in: photo))
    }

    /// Turned, the frame shrinks about its center, keeps its shape, and leaves no empty corner.
    @Test func aTurnedFrameIsFittedInThePhoto() {
        var turned = PhotoCrop.whole
        turned.angle = 10
        let fitted = turned.fitted(in: photo)
        #expect(fitted.fits(in: photo))
        #expect(fitted.width < 1 && fitted.width > 0.6)
        #expect(abs(fitted.left + fitted.width / 2 - 0.5) < 1e-6)
        #expect(abs(fitted.top + fitted.height / 2 - 0.5) < 1e-6)
        #expect(abs(pixelAspect(fitted) - 1.5) < 1e-6)
        // As large as it can be: a little larger would not fit.
        var larger = fitted
        larger.width *= 1.01
        larger.height *= 1.01
        larger.left = 0.5 - larger.width / 2
        larger.top = 0.5 - larger.height / 2
        #expect(!larger.fits(in: photo))
    }

    @Test func theLargestFrameOfAShapeIsInTheMiddle() {
        let square = PhotoCrop.whole.largest(aspect: 1, in: photo)
        #expect(abs(pixelAspect(square) - 1) < 1e-6)
        #expect(abs(square.height - 1) < 1e-9)
        #expect(abs(square.left + square.width / 2 - 0.5) < 1e-9)
        let upright = PhotoCrop(left: 0, top: 0, width: 1, height: 1, angle: 3).largest(aspect: 4.0 / 5, in: photo)
        #expect(abs(pixelAspect(upright) - 0.8) < 1e-6)
        #expect(upright.fits(in: photo))
    }

    @Test func aDragStopsAtTheEdgeOfThePhoto() {
        let half = PhotoCrop(left: 0.25, top: 0.25, width: 0.5, height: 0.5)
        // Moved far to the right: it stops against the right edge, at the same height.
        let moved = half.dragged(.inside, by: CGSize(width: 0.9, height: 0), aspect: nil, in: photo)
        #expect(abs(moved.left - 0.5) < 1e-6 && abs(moved.top - 0.25) < 1e-9)
        #expect(abs(moved.width - 0.5) < 1e-9)
        // An edge pulled past the photo stops at its edge.
        let wider = half.dragged(.left, by: CGSize(width: -0.6, height: 0), aspect: nil, in: photo)
        #expect(abs(wider.left) < 1e-6 && abs(wider.left + wider.width - 0.75) < 1e-9)
        // An edge pushed past the other keeps the frame at its smallest.
        let narrow = half.dragged(.right, by: CGSize(width: -0.9, height: 0), aspect: nil, in: photo)
        #expect(narrow.width > 0 && narrow.width < 0.05 && abs(narrow.left - 0.25) < 1e-9)
    }

    @Test func aCornerDraggedKeepsTheShape() {
        let square = PhotoCrop(left: 0.3, top: 0.2, width: 0.4 * 4000 / 6000, height: 0.4)
        let grown = square.dragged(.bottomRight, by: CGSize(width: 0.1, height: 0.02), aspect: 1, in: photo)
        #expect(abs(pixelAspect(grown) - 1) < 1e-6)
        // The opposite corner stays where it was.
        #expect(abs(grown.left - 0.3) < 1e-9 && abs(grown.top - 0.2) < 1e-9)
        #expect(grown.width > square.width)
        // An edge drags the other side along, about its center.
        let taller = square.dragged(.top, by: CGSize(width: 0, height: -0.1), aspect: 1, in: photo)
        #expect(abs(pixelAspect(taller) - 1) < 1e-6)
        #expect(abs(taller.left + taller.width / 2 - (square.left + square.width / 2)) < 1e-9)
        #expect(abs(taller.top + taller.height - 0.6) < 1e-9)
    }

    /// A quarter turn and a mirror take the frame with the picture, and four turns or two
    /// mirrors give it back.
    @Test func turningAndMirroringTakeTheFrameAlong() throws {
        let frame = PhotoCrop(left: 0.1, top: 0.2, width: 0.3, height: 0.5, angle: 4)
        let turned = frame.turnedLeft()
        // The left side of the photo goes to the bottom: the frame's left edge with it.
        #expect(abs(turned.top + turned.height - 0.9) < 1e-9 && abs(turned.left - 0.2) < 1e-9)
        #expect(turned.quarterTurns == 3 && turned.angle == 4)
        #expect(turned.framedSize(of: photo).width == frame.framedSize(of: photo).height)
        #expect(turned.orientedSize(of: photo) == CGSize(width: 4000, height: 6000))
        #expect(frame.turnedLeft().turnedLeft().turnedLeft().turnedLeft().isClose(to: frame))
        #expect(frame.flipped().flipped().isClose(to: frame))
        // Under the mirror, a turn to the left is a turn to the right of the photo itself.
        let mirrored = frame.flipped()
        #expect(abs(mirrored.left - 0.6) < 1e-9 && mirrored.angle == -4 && mirrored.isFlipped)
        #expect(mirrored.turnedLeft().quarterTurns == 1)
        #expect(!PhotoCrop.whole.turnedLeft().isWhole && !PhotoCrop.whole.flipped().isWhole)
        #expect(PhotoCrop.whole.turnedLeft().fits(in: photo))

        // A frame saved before photos could be turned is neither turned nor mirrored.
        let older = Data(#"{"left": 0.1, "top": 0.2, "width": 0.3, "height": 0.5, "angle": 4}"#.utf8)
        #expect(try JSONDecoder().decode(PhotoCrop.self, from: older) == frame)
    }

    /// The frame is the photo's own: no recipe holds it, pasting does not carry it, and the
    /// engine never sees it.
    @Test func theFrameBelongsToThePhoto() throws {
        let crop = PhotoCrop(left: 0.1, top: 0.1, width: 0.5, height: 0.5, angle: 2)
        var framed = DevelopSettings()
        framed.crop = crop
        framed.exposureEV = 1
        #expect(Recipe(name: "Framed", from: framed).look.crop == nil)
        let other = DevelopSettings()
        #expect(other.takingLook(of: framed).crop == nil)
        #expect(framed.takingLook(of: other).crop == crop)
        #expect(try !framed.enginePatchJSON().contains("crop"))
        #expect(try framed.enginePatchJSON() == DevelopSettings(exposureEV: 1).enginePatchJSON())

        // Kept with the photo and read back; settings saved before there were frames have none.
        let data = try JSONEncoder().encode(framed)
        #expect(try JSONDecoder().decode(DevelopSettings.self, from: data).crop == crop)
        let older = try JSONDecoder().decode(DevelopSettings.self, from: Data(#"{"exposureEV": 1}"#.utf8))
        #expect(older.crop == nil)
    }

    /// The decoder hands the engine the framed picture, at the size asked for it.
    @Test func theDecoderFramesThePhoto() async throws {
        let url = try TestDNG.writeGrayCard(width: 600, height: 400)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let leftHalf = PhotoCrop(left: 0, top: 0, width: 0.5, height: 1)
        #expect(decoder.longSide(framedBy: leftHalf) == 400)

        let whole = try await decoder.decode(crop: leftHalf)
        #expect(whole.width == 300 && whole.height == 400)
        // The size asked is the framed picture's.
        let preview = try await decoder.decode(maxDimension: 100, crop: leftHalf)
        #expect(preview.width == 75 && preview.height == 100)

        // The left half is the gray card, all of it.
        let pixels = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, crop: leftHalf)
        let green = { (column: Int) in
            pixels.pixels.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: (pixels.height / 2 * pixels.width + column) * 16 + 4, as: Float.self)
            }
        }
        #expect(abs(green(pixels.width - 2) - green(1)) < 0.005)
        #expect(abs(green(pixels.width / 2) - 0.18) < 0.02)

        // Turned a quarter to the left, the gray card on the left goes to the bottom; mirrored,
        // to the right.
        let turnedLeft = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, crop: PhotoCrop.whole.turnedLeft())
        #expect(turnedLeft.width == 400 && turnedLeft.height == 600)
        let greenAt = { (decoded: DecodedPixels, column: Int, row: Int) in
            decoded.pixels.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: (row * decoded.width + column) * 16 + 4, as: Float.self)
            }
        }
        #expect(abs(greenAt(turnedLeft, 200, 590) - 0.18) < 0.02)
        #expect(abs(greenAt(turnedLeft, 200, 10) - 0.18) > 0.02)
        let mirrored = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, crop: PhotoCrop.whole.flipped())
        #expect(abs(greenAt(mirrored, 590, 200) - 0.18) < 0.02)
        #expect(abs(greenAt(mirrored, 10, 200) - 0.18) > 0.02)

        // Turned, the picture is smaller than the frame's rectangle would be without turning.
        var turned = PhotoCrop.whole
        turned.angle = 8
        let straightened = try await decoder.decode(crop: turned.fitted(in: decoder.size))
        #expect(straightened.width < 600 && straightened.height < 400)
        #expect(abs(Double(straightened.width) / Double(straightened.height) - 1.5) < 0.02)
    }

    @Test func aRightTurnUndoesALeftTurn() {
        let crop = PhotoCrop(left: 0.1, top: 0.2, width: 0.5, height: 0.6, quarterTurns: 1, isFlipped: true)
        #expect(crop.turnedLeft().turnedRight().isClose(to: crop))
        #expect(PhotoCrop(left: 0, top: 0, width: 1, height: 1).turnedRight().swapsSides)
        #expect(!PhotoCrop(left: 0, top: 0, width: 1, height: 1).reorients)
    }

    @Test func aTurnedThumbnailSwapsItsSides() throws {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        let thumbnail = try #require(context.makeImage())
        let turned = try #require(ImageLoader.oriented(
            thumbnail, by: PhotoCrop(left: 0, top: 0, width: 1, height: 1).turnedRight(),
        ))
        #expect(turned.width == 20 && turned.height == 40)
    }
}

extension PhotoCrop {
    /// The same frame, but for the rounding of its edges.
    func isClose(to other: PhotoCrop) -> Bool {
        let edges = [left - other.left, top - other.top, width - other.width, height - other.height, angle - other.angle]
        return edges.allSatisfy { abs($0) < 1e-9 } && quarterTurns == other.quarterTurns && isFlipped == other.isFlipped
    }

}
