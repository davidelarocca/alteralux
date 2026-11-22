import CoreImage
import Foundation
import Testing
@testable import AlteraluxKit

/// The RAW decoder's highlight recovery and noise reduction: what it offers a photo, what it is
/// told, and what a recipe does with them.
struct RawDecodingTests {
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AlteraluxKitTests
        .deletingLastPathComponent() // Tests
        .appendingPathComponent("Fixtures/gray-card.dng")

    @Test func aRawOffersTheDecodersOptionsAndOtherFilesDoNot() throws {
        let decoder = try PhotoDecoder(url: Self.fixture)
        let defaults = try #require(decoder.rawDefaults)
        let filter = try #require(CIRAWFilter(imageURL: Self.fixture))
        #expect(defaults == RawDecodingDefaults(filter: filter))
        #expect(defaults.offersAny)

        let png = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: png) }
        let image = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        try CIContext().writePNGRepresentation(
            of: image, to: png, format: .RGBA8, colorSpace: #require(CGColorSpace(name: CGColorSpace.sRGB)),
        )
        #expect(try PhotoDecoder(url: png).rawDefaults == nil)
    }

    /// The decoder is kept between decodes: what is asked reaches it, and what is no longer asked
    /// goes back to the photo's own choice.
    @Test func theOptionsReachTheDecoderAndGoBack() throws {
        let filter = try #require(CIRAWFilter(imageURL: Self.fixture))
        let defaults = RawDecodingDefaults(filter: filter)
        let asked = RawDecodingOptions(
            highlightRecovery: false, luminanceNoiseReduction: 0.8, colorNoiseReduction: 0.1, moireReduction: 0.9,
        )
        defaults.apply(asked, to: filter)
        if defaults.highlightRecovery != nil {
            #expect(filter.isHighlightRecoveryEnabled == false)
        }
        if defaults.luminanceNoiseReduction != nil {
            #expect(abs(filter.luminanceNoiseReductionAmount - 0.8) < 1e-6)
        }
        if defaults.colorNoiseReduction != nil {
            #expect(abs(filter.colorNoiseReductionAmount - 0.1) < 1e-6)
        }
        if defaults.moireReduction != nil {
            #expect(abs(filter.moireReductionAmount - 0.9) < 1e-6)
        }
        defaults.apply(RawDecodingOptions(), to: filter)
        #expect(RawDecodingDefaults(filter: filter) == defaults)
    }

    @Test func aRecipeLeavesThePhotosNoiseReduction() {
        var photo = DevelopSettings()
        photo.rawDecoding.luminanceNoiseReduction = 0.6
        var other = DevelopSettings()
        other.rawDecoding = RawDecodingOptions(highlightRecovery: false, colorNoiseReduction: 1)
        other.grainParticleArea = 0.5
        let result = photo.takingLook(of: other)
        #expect(result.rawDecoding == photo.rawDecoding)
        #expect(result.grainParticleArea == 0.5)
    }

    @Test func settingsSavedBeforeTheOptionsLeaveTheDecodersChoice() throws {
        let saved = try JSONDecoder().decode(DevelopSettings.self, from: Data(#"{"exposureEV": 0.5}"#.utf8))
        #expect(saved.rawDecoding == RawDecodingOptions())
        var settings = DevelopSettings()
        settings.rawDecoding.moireReduction = 0.3
        let read = try JSONDecoder().decode(DevelopSettings.self, from: JSONEncoder().encode(settings))
        #expect(read.rawDecoding.moireReduction == 0.3)
    }
}
