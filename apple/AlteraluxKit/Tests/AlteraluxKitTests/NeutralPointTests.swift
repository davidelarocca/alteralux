import CoreImage
import Foundation
import Testing
@testable import AlteraluxKit

/// The white balance of the dropper: the one that makes the point clicked gray, measured where
/// the user saw it, in the photo framed as the adjustments frame it.
struct NeutralPointTests {
    /// The red, green and blue at `point` (0 to 1 from the top left) of the photo decoded with
    /// `whiteBalance` and `crop`, green 1.
    private func color(
        _ decoder: PhotoDecoder, at point: CGPoint, whiteBalance: WhiteBalance?, crop: PhotoCrop? = nil,
    ) async throws -> SIMD3<Double> {
        let decoded = try await decoder.pixels(maxDimension: nil, whiteBalance: whiteBalance, crop: crop)
        let column = min(decoded.width - 1, Int(point.x * Double(decoded.width)))
        let row = min(decoded.height - 1, Int(point.y * Double(decoded.height)))
        let offset = (row * decoded.width + column) * 16
        let color = decoded.pixels.withUnsafeBytes { buffer in
            SIMD3(
                Double(buffer.loadUnaligned(fromByteOffset: offset, as: Float.self)),
                Double(buffer.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)),
                Double(buffer.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)),
            )
        }
        return color / color.y
    }

    private func isGray(_ color: SIMD3<Double>) -> Bool {
        abs(color.x - 1) < 0.03 && abs(color.z - 1) < 0.03
    }

    @Test func aGrayTheCameraGotWrongComesOutGray() async throws {
        // The camera recorded less blue in white than the light had: as shot, the gray is blue.
        let url = try TestDNG.writeGrayScene(asShotNeutral: [1, 1, 0.6])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let point = CGPoint(x: 0.5, y: 0.5)
        let before = try await color(decoder, at: point, whiteBalance: nil)
        #expect(!isGray(before), "as shot: \(before)")

        let picked = try #require(try await decoder.whiteBalance(neutralAt: point, settings: DevelopSettings()))
        let after = try await color(decoder, at: point, whiteBalance: picked)
        // All the way to gray, not part of the way as the automatic white balance goes.
        #expect(isGray(after), "picked \(picked): \(after)")
    }

    @Test func aGrayAlreadyGrayKeepsTheWhiteBalance() async throws {
        let url = try TestDNG.writeGrayCard()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let asShot = try #require(decoder.asShotWhiteBalance)
        // The gray card, on the left half.
        let picked = try #require(
            try await decoder.whiteBalance(neutralAt: CGPoint(x: 0.25, y: 0.5), settings: DevelopSettings()),
        )
        #expect(abs(picked.temperature - asShot.temperature) < 50 && abs(picked.tint - asShot.tint) < 2, "\(picked)")
    }

    @Test func aWarmPointMakesTheLightWarmer() async throws {
        let url = try TestDNG.writeGrayCard()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let asShot = try #require(decoder.asShotWhiteBalance)
        // The warm ramp, on the right half: taken as gray, the light was warmer than the camera said.
        let point = CGPoint(x: 0.75, y: 0.5)
        let picked = try #require(try await decoder.whiteBalance(neutralAt: point, settings: DevelopSettings()))
        #expect(picked.temperature < asShot.temperature - 500, "\(picked)")
        #expect(try await isGray(color(decoder, at: point, whiteBalance: picked)))
    }

    @Test func thePointIsWhereItIsSeenInTheFrame() async throws {
        let url = try TestDNG.writeGrayCard()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let asShot = try #require(decoder.asShotWhiteBalance)
        // Turned half a turn, the warm ramp is on the left of what is on screen.
        let crop = PhotoCrop(left: 0, top: 0, width: 1, height: 1, quarterTurns: 2)
        var settings = DevelopSettings()
        settings.crop = crop
        let point = CGPoint(x: 0.25, y: 0.5)
        let picked = try #require(try await decoder.whiteBalance(neutralAt: point, settings: settings))
        #expect(picked.temperature < asShot.temperature - 500, "\(picked)")
        #expect(try await isGray(color(decoder, at: point, whiteBalance: picked, crop: crop)))
    }

    @Test func pixelsClippedOrNearlyBlackCannotBeMadeGray() {
        #expect(NeutralPoint.mean([Float](repeating: 1, count: 196), count: 49) == nil)
        #expect(NeutralPoint.mean([Float](repeating: 0.001, count: 196), count: 49) == nil)
        let gray = try? #require(NeutralPoint.mean([Float](repeating: 0.18, count: 196), count: 49))
        #expect(gray.map { abs($0.x - 0.18) < 0.0001 && abs($0.z - 0.18) < 0.0001 } == true)
    }

    @Test func aFileThatIsNotRawHasNoWhiteBalanceToPick() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-test-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        try CIContext().writeTIFFRepresentation(
            of: image, to: url, format: .RGBA8, colorSpace: #require(CGColorSpace(name: CGColorSpace.sRGB)),
        )
        let decoder = try PhotoDecoder(url: url)
        #expect(try await decoder.whiteBalance(neutralAt: CGPoint(x: 0.5, y: 0.5), settings: DevelopSettings()) == nil)
    }
}
