@testable import AlteraluxKit
import Foundation
import Testing

/// What a render smaller than the photo changes of the lengths the engine takes in pixels.
struct PixelScalingTests {
    /// At a third of the photo's size the grain's 0.65 pixels become about 0.43: the blur that
    /// takes as much from the grain as the photo's blur still does once seen at that size. The
    /// same reckoning as the engine's own render measured in `PreviewFidelityTests` (0.44).
    @Test func theGrainsBlurTakesWhatThePhotosBlurStillTakesAtTheRendersSize() {
        #expect(abs(PixelScaling.grainBlur(0.65, scale: 1.0 / 3) - 0.43) < 0.01)
        // At a sixth, the lightest blur the engine draws is the closest.
        let sixth = PixelScaling.grainBlur(0.65, scale: 1.0 / 6)
        #expect(sixth > PixelScaling.grainBlurThreshold && sixth < 0.41)
        // A fraction of a pixel left over counts in part.
        let between = PixelScaling.grainBlur(0.65, scale: 1 / 4.5)
        #expect(between < PixelScaling.grainBlur(0.65, scale: 1.0 / 3))
    }

    @Test func theWholePhotoAndAnUnblurredGrainAreLeftAsTheyAre() {
        #expect(PixelScaling.grainBlur(0.65, scale: 1) == 0.65)
        #expect(PixelScaling.grainBlur(0.3, scale: 0.25) == 0.3)
        #expect(PixelScaling.sharpenAmount(0.7, scale: 1) == 0.7)
    }

    /// A strong blur stays strong where a pixel of the render holds few of the photo's.
    @Test func aBlurOfSeveralPixelsStaysAboveTheThreshold() {
        let blur = PixelScaling.grainBlur(3, scale: 0.5)
        #expect(blur > 1 && blur < 3)
    }

    @Test func theSharpeningsStrengthFollowsTheSize() {
        #expect(abs(PixelScaling.sharpenAmount(0.7, scale: 0.25) - 0.175) < 1e-9)
    }

    /// The engine's patch for a preview: only the lengths in pixels change, the radius of the
    /// sharpening and the glare's blur included as they were.
    @Test func aPreviewsPatchChangesOnlyTheLengthsInPixels() throws {
        var settings = DevelopSettings()
        settings.scanner.lensBlur = 1.5
        let export = try Self.object(settings.enginePatchJSON())
        let preview = try Self.object(settings.enginePatchJSON(pixelScale: 1.0 / 3))

        let grain = try #require(((preview["film_render"] as? [String: Any])?["grain"] as? [String: Any])?["blur"] as? Double)
        #expect(abs(grain - 0.43) < 0.01)
        let scanner = try #require(preview["scanner"] as? [String: Any])
        #expect(scanner["unsharp_mask"] as? [Double] == [0.7, 0.7 / 3])
        #expect(abs((scanner["lens_blur"] as? Double ?? 0) - 0.5) < 1e-9)
        let glare = ((preview["print_render"] as? [String: Any])?["glare"] as? [String: Any])?["blur"] as? Double
        #expect(glare == 0.5)

        // Everything else is the export's.
        var rest = preview, exportRest = export
        for key in ["film_render", "scanner"] {
            rest[key] = nil
            exportRest[key] = nil
        }
        #expect(NSDictionary(dictionary: rest).isEqual(to: exportRest))
        #expect(try settings.enginePatchJSON(pixelScale: 1) == settings.enginePatchJSON())
    }

    @Test func aRenderIsScaledByItsLongSideOverThePhotos() {
        #expect(FilmRenderer.pixelScale(sourceLongSide: 2048, maxDimension: 0, photoLongSide: 6144) == 1.0 / 3)
        #expect(FilmRenderer.pixelScale(sourceLongSide: 6144, maxDimension: 1024, photoLongSide: 6144) == 1.0 / 6)
        #expect(FilmRenderer.pixelScale(sourceLongSide: 2048, maxDimension: 0, photoLongSide: nil) == 1)
        // Never larger than the photo.
        #expect(FilmRenderer.pixelScale(sourceLongSide: 6144, maxDimension: 0, photoLongSide: 2048) == 1)
    }

    private static func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}
