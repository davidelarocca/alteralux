import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxKit

/// The RAW file kept for the tests of the other targets, which cannot use `TestDNG`.
private let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxKitTests
    .deletingLastPathComponent() // Tests
    .appendingPathComponent("Fixtures/gray-card.dng")

/// Decoding a photo for each preview, and a RAW with the white balance chosen.
struct PhotoDecoderTests {
    /// A scene-linear color.
    private struct Color: CustomStringConvertible {
        let red: Float
        let green: Float
        let blue: Float

        var description: String {
            "(\(red), \(green), \(blue))"
        }
    }

    /// The gray card in the left half of the test RAW, as it is decoded.
    private func grayCard(
        of decoder: PhotoDecoder, maxDimension: Int? = nil, whiteBalance: WhiteBalance? = nil,
    ) async throws -> Color {
        let decoded = try await decoder.pixels(maxDimension: maxDimension, whiteBalance: whiteBalance)
        let offset = (decoded.height / 2 * decoded.width + decoded.width / 4) * 16
        return decoded.pixels.withUnsafeBytes { buffer in
            Color(
                red: buffer.loadUnaligned(fromByteOffset: offset, as: Float.self),
                green: buffer.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                blue: buffer.loadUnaligned(fromByteOffset: offset + 8, as: Float.self),
            )
        }
    }

    @Test func aRawIsOpenedWithTheWhiteBalanceTheCameraRecorded() async throws {
        let url = try TestDNG.writeGrayCard()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        #expect(decoder.isRaw)
        #expect(decoder.width == 240 && decoder.height == 160)
        // The test camera sees in sRGB under daylight and recorded a neutral white.
        let asShot = try #require(decoder.asShotWhiteBalance)
        #expect(abs(asShot.temperature - 6500) < 100, "as shot: \(asShot)")

        let loaded = try await decoder.decode()
        #expect(loaded.isRaw && loaded.width == 240 && loaded.height == 160)
        // A gray card stays gray, and about as bright as it was.
        let gray = try await grayCard(of: decoder)
        #expect(abs(gray.red - gray.blue) < 0.005 && abs(gray.red - gray.green) < 0.005, "gray card: \(gray)")
        #expect(abs(gray.green - 0.18) < 0.02, "gray card: \(gray)")
    }

    @Test func theDecoderScalesThePhotoForAPreview() async throws {
        let url = try TestDNG.writeGrayCard(width: 600, height: 400)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let preview = try await decoder.decode(maxDimension: 150)
        #expect(preview.width == 150 && preview.height == 100)
        // Never larger than the photo, and 0 is the whole of it.
        let whole = try await decoder.decode(maxDimension: 4000)
        #expect(whole.width == 600 && whole.height == 400)
        let zero = try await decoder.decode(maxDimension: 0)
        #expect(zero.width == 600)
        // The loader that decodes a file once goes the same way.
        let loaded = try ImageLoader.load(url, maxDimension: 150)
        #expect(loaded.isRaw && loaded.width == 150 && loaded.height == 100)
    }

    /// The temperature is that of the light: called warmer than it was, the photo turns cooler.
    @Test func theWhiteBalanceMovesTheColors() async throws {
        let url = try TestDNG.writeGrayCard()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let asShot = try #require(decoder.asShotWhiteBalance)

        let cooler = try await grayCard(of: decoder, whiteBalance: WhiteBalance(temperature: 4000, tint: asShot.tint))
        #expect(cooler.blue > cooler.red * 1.5, "at 4000 K: \(cooler)")
        let warmer = try await grayCard(of: decoder, whiteBalance: WhiteBalance(temperature: 9000, tint: asShot.tint))
        #expect(warmer.red > warmer.blue * 1.2, "at 9000 K: \(warmer)")
        let tinted = try await grayCard(
            of: decoder, whiteBalance: WhiteBalance(temperature: asShot.temperature, tint: asShot.tint + 40),
        )
        #expect(tinted.green < tinted.red && tinted.green < tinted.blue, "tint +40: \(tinted)")

        // Back to what the camera recorded, by name or by saying nothing.
        let neutral = try await grayCard(of: decoder)
        let named = try await grayCard(of: decoder, whiteBalance: asShot)
        #expect(abs(neutral.red - neutral.blue) < 0.005, "as shot again: \(neutral)")
        #expect(abs(named.red - neutral.red) < 0.001 && abs(named.blue - neutral.blue) < 0.001)
        // At any size.
        let small = try await grayCard(of: decoder, maxDimension: 60, whiteBalance: WhiteBalance(temperature: 4000, tint: asShot.tint))
        #expect(abs(small.blue / small.red - cooler.blue / cooler.red) < 0.05, "at 4000 K, reduced: \(small)")
    }

    @Test func aFileThatIsNotARawKeepsItsWhiteBalance() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alteralux-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(
            CGContext(
                data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ),
        )
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
        )
        try CGImageDestinationAddImage(destination, #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        let decoder = try PhotoDecoder(url: url)
        #expect(!decoder.isRaw && decoder.asShotWhiteBalance == nil)
        #expect(decoder.width == 64 && decoder.height == 48)
        let plain = try await grayCard(of: decoder)
        let asked = try await grayCard(of: decoder, whiteBalance: WhiteBalance(temperature: 3000, tint: 0))
        #expect(plain.red == asked.red && plain.blue == asked.blue)
        // Nothing to measure or to correct either.
        #expect(await decoder.automaticWhiteBalance() == nil)
        #expect(await decoder.whiteBalance(for: DevelopSettings(autoWhiteBalance: true)) == nil)
        #expect(!decoder.correctsLens)
        let reduced = try await decoder.decode(maxDimension: 32)
        #expect(reduced.width == 32 && reduced.height == 24)
    }

    @Test func aFileThatCannotBeReadIsReported() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing.dng")
        #expect(throws: AlteraluxError.self) { _ = try PhotoDecoder(url: missing) }
        // A RAW the decoder refuses: it is too small for it.
        let tiny = try TestDNG.writeGrayCard(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: tiny) }
        #expect(throws: AlteraluxError.self) { _ = try PhotoDecoder(url: tiny) }
        #expect(throws: AlteraluxError.self) { _ = try ImageLoader.load(tiny) }
    }

    /// The interface tests open this file; it is what `TestDNG` writes.
    @Test func theFixtureIsTheTestRaw() throws {
        #expect(try Data(contentsOf: fixture) == TestDNG.grayCard())
    }

    @Test func aWhiteBalanceChosenByHandWinsOverTheAutomaticOne() {
        let asShot = WhiteBalance(temperature: 5200, tint: 8)
        let automatic = WhiteBalance(temperature: 4400, tint: 2)
        #expect(DevelopSettings().whiteBalance(asShot: asShot, automatic: automatic) == automatic)
        var settings = DevelopSettings()
        settings.temperature = 6000
        #expect(settings.whiteBalance(asShot: asShot, automatic: automatic) == WhiteBalance(temperature: 6000, tint: 8))
    }

    @Test func adjustmentsSavedBeforeTheNewChoicesKeepTheirLook() throws {
        // Saved by a version without automatic white balance and lens correction.
        let old = try JSONDecoder().decode(DevelopSettings.self, from: Data(#"{"filmID":"kodak_portra_400"}"#.utf8))
        #expect(!old.autoWhiteBalance)
        #expect(old.lensCorrection == nil)
        // New photos have the lens corrected.
        #expect(DevelopSettings().lensCorrection == true)
    }

    @Test func theTestRawHasNoLensToCorrect() async throws {
        let url = try TestDNG.writeGrayCard()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        #expect(!decoder.correctsLens)
        // Asking for a correction that is not known decodes the photo as it is.
        let plain = try await decoder.pixels(maxDimension: nil, whiteBalance: nil)
        let corrected = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, lensCorrection: true)
        #expect(plain.pixels == corrected.pixels)
    }

    @Test func settingsNameAWhiteBalanceOverTheCameras() throws {
        let asShot = WhiteBalance(temperature: 5200, tint: 8)
        #expect(DevelopSettings().whiteBalance(asShot: asShot) == asShot)
        var settings = DevelopSettings()
        settings.temperature = 4000
        #expect(settings.whiteBalance(asShot: asShot) == WhiteBalance(temperature: 4000, tint: 8))
        // The engine is not told: the white balance is set before the film sees the photo.
        let patch = try settings.enginePatchJSON()
        #expect(try patch == DevelopSettings().enginePatchJSON())
    }
}
