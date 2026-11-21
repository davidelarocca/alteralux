import Foundation
import Testing
@testable import AlteraluxKit

/// The automatic white balance, on RAWs of a gray scene whose camera got the light right or
/// wrong, and the rule that keeps the camera's when the two are close.
struct AutomaticWhiteBalanceTests {
    /// The red, green and blue of the middle of the photo decoded with `whiteBalance`, green 1.
    private func colorOfGray(_ decoder: PhotoDecoder, whiteBalance: WhiteBalance?) async throws -> SIMD3<Double> {
        let decoded = try await decoder.pixels(maxDimension: nil, whiteBalance: whiteBalance)
        let offset = (decoded.height / 2 * decoded.width + decoded.width / 2) * 16
        let color = decoded.pixels.withUnsafeBytes { buffer in
            SIMD3(
                Double(buffer.loadUnaligned(fromByteOffset: offset, as: Float.self)),
                Double(buffer.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)),
                Double(buffer.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)),
            )
        }
        return color / color.y
    }

    @Test func aCameraThatGotTheLightRightIsKept() async throws {
        let url = try TestDNG.writeGrayScene(asShotNeutral: [1, 1, 1])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let asShot = try #require(decoder.asShotWhiteBalance)
        #expect(await decoder.automaticWhiteBalance() == asShot)
    }

    @Test func aCameraThatGotTheLightWrongIsCorrected() async throws {
        // The camera recorded less blue in white than the light had: decoded as shot, the gray
        // scene comes out blue.
        let url = try TestDNG.writeGrayScene(asShotNeutral: [1, 1, 0.6])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let asShot = try #require(decoder.asShotWhiteBalance)
        let automatic = try #require(await decoder.automaticWhiteBalance())
        #expect(automatic != asShot)

        let before = try await colorOfGray(decoder, whiteBalance: asShot)
        let after = try await colorOfGray(decoder, whiteBalance: automatic)
        #expect(before.z / before.x > 1.3, "as shot: \(before)")
        // Part of the way back to gray: the gray is at least halfway less blue.
        let castBefore = abs(before.z / before.x - 1)
        let castAfter = abs(after.z / after.x - 1)
        #expect(castAfter < castBefore / 2, "as shot \(before), automatic \(after)")
        // Measuring once is enough: the second answer is the first.
        #expect(await decoder.automaticWhiteBalance() == automatic)
    }

    @Test func theDecoderIsLeftWithTheCamerasWhiteBalance() async throws {
        let url = try TestDNG.writeGrayScene(asShotNeutral: [1, 1, 0.6])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let before = try await colorOfGray(decoder, whiteBalance: nil)
        _ = await decoder.automaticWhiteBalance()
        let after = try await colorOfGray(decoder, whiteBalance: nil)
        #expect(abs(before.x - after.x) < 0.001 && abs(before.z - after.z) < 0.001)
    }

    @Test func pixelsTooDarkOrClippedAreNotMeasured() {
        let clipped = [Float](repeating: 1, count: 400)
        #expect(AutomaticWhiteBalance.shadesOfGray(clipped, count: 100) == nil)
        let dark = [Float](repeating: 0.001, count: 400)
        #expect(AutomaticWhiteBalance.shadesOfGray(dark, count: 100) == nil)
        let gray = [Float](repeating: 0.18, count: 400)
        let mean = try? #require(AutomaticWhiteBalance.shadesOfGray(gray, count: 100))
        #expect(mean.map { abs($0.x - 0.18) < 0.001 && abs($0.z - 0.18) < 0.001 } == true)
    }

    @Test func aWhiteBalanceCloseToTheCamerasKeepsTheCameras() {
        let asShot = WhiteBalance(temperature: 5000, tint: 5)
        // 5300 K is 11 mired from 5000 K; a tint 10 away.
        let close = WhiteBalance(temperature: 5300, tint: 15)
        #expect(AutomaticWhiteBalance.adopted(close, asShot: asShot) == asShot)
    }

    @Test func aWhiteBalanceFarFromTheCamerasMovesPartOfTheWay() {
        let asShot = WhiteBalance(temperature: 5000, tint: 0)
        // 4000 K is 50 mired warmer than 5000 K.
        let adopted = AutomaticWhiteBalance.adopted(WhiteBalance(temperature: 4000, tint: 0), asShot: asShot)
        let mired = 1_000_000 / adopted.temperature
        #expect(abs(mired - (200 + 0.6 * 50)) < 0.01, "adopted: \(adopted)")
        #expect(adopted.tint == 0)
        // A tint far off moves the tint alone.
        let tinted = AutomaticWhiteBalance.adopted(WhiteBalance(temperature: 5000, tint: 40), asShot: asShot)
        #expect(tinted.temperature == 5000 && abs(tinted.tint - 24) < 0.01)
    }

    @Test func theResultStaysWithinTheSliders() {
        let asShot = WhiteBalance(temperature: 11000, tint: 140)
        let adopted = AutomaticWhiteBalance.adopted(WhiteBalance(temperature: 100_000, tint: 400), asShot: asShot)
        #expect(adopted.temperature <= 12000 && adopted.tint <= 150)
    }
}
