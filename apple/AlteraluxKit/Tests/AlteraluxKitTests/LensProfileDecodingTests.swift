import Foundation
import Testing
@testable import AlteraluxKit

/// A RAW whose lens Apple's decoder does not know, corrected with a lens profile: found from the
/// camera and lens the photo names, applied when the lens correction is on.
struct LensProfileDecodingTests {
    private let taken = PhotoLensInfo(
        cameraMaker: "SONY", cameraModel: "ILCE-7M3", lensModel: "FE 24-70mm F2.8 GM", focalLength: 24, aperture: 2.8,
    )

    @Test func thePhotoNamesItsCameraAndLens() throws {
        let url = try TestDNG.writeGrayCard(takenWith: taken)
        defer { try? FileManager.default.removeItem(at: url) }
        let info = try #require(PhotoLensInfo.read(from: url))
        #expect(info.cameraModel == "ILCE-7M3" && info.lensModel == "FE 24-70mm F2.8 GM")
        #expect(info.focalLength == 24 && info.aperture == 2.8)
    }

    @Test func aKnownLensIsCorrectedWhenAsked() async throws {
        let url = try TestDNG.writeGrayCard(takenWith: taken)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url, lenses: LensDatabase(directory: lensFixtureDirectory))
        let profile = try #require(decoder.lensProfile)
        #expect(profile.lensName.contains("24-70mm f/2.8 GM"))
        #expect(decoder.correctsLens && !decoder.correctsLensByDefault)

        let plain = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, lensCorrection: false)
        let corrected = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, lensCorrection: true)
        #expect(plain.pixels != corrected.pixels)
        #expect(corrected.width == plain.width && corrected.height == plain.height)
        // Adjustments saved before the choice existed keep the photo as it was.
        let old = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, lensCorrection: nil)
        #expect(old.pixels == plain.pixels)
    }

    @Test func withoutProfilesNothingIsCorrected() throws {
        let url = try TestDNG.writeGrayCard(takenWith: taken)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        #expect(decoder.lensProfile == nil && !decoder.correctsLens)
    }

    @Test func anUnknownLensIsNotCorrected() throws {
        var other = taken
        other.lensModel = "Some 50mm F1.4 nobody measured"
        let url = try TestDNG.writeGrayCard(takenWith: other)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url, lenses: LensDatabase(directory: lensFixtureDirectory))
        #expect(decoder.lensProfile == nil && !decoder.correctsLens)
    }
}
