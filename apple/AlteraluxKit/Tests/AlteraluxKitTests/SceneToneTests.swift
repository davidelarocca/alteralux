import AlteraluxEngine
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxKit

/// The upstream data folder, straight from the git submodule.
private let toneDataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxKitTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // AlteraluxKit
    .deletingLastPathComponent() // apple
    .deletingLastPathComponent() // repository root
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

/// The scene's highlights and shadows, changed after the exposure and before the film (ADR 0019).
struct SceneToneTests {
    // MARK: - The curve

    @Test func middleGrayStaysAndEachEndMovesByItsSlider() {
        let gray = SceneTone.middleGray
        let both = SceneTone(highlights: -1, shadows: 1)
        #expect(both.stops(atLuminance: gray) == 0)
        // The far ends move by the whole reach, and stay there past them.
        #expect(abs(both.stops(atLuminance: gray * pow(2, -SceneTone.shadowSpan)) - SceneTone.reach) < 1e-9)
        #expect(abs(both.stops(atLuminance: gray * pow(2, -12)) - SceneTone.reach) < 1e-9)
        #expect(abs(both.stops(atLuminance: gray * pow(2, SceneTone.highlightSpan)) + SceneTone.reach) < 1e-9)
        #expect(abs(both.stops(atLuminance: gray * pow(2, 9)) + SceneTone.reach) < 1e-9)
        // Each slider leaves the other end alone.
        #expect(SceneTone(highlights: -1).stops(atLuminance: gray / 8) == 0)
        #expect(SceneTone(shadows: 1).stops(atLuminance: gray * 4) == 0)
        // Halfway down the shadows, half the lift.
        let half = SceneTone(shadows: 0.5).stops(atLuminance: gray * pow(2, -SceneTone.shadowSpan / 2))
        #expect(abs(half - 0.5 * SceneTone.reach * 0.5) < 1e-9)
        #expect(SceneTone().isNeutral && !both.isNeutral)
    }

    /// However far the sliders go, a brighter part of the scene stays brighter than a darker one.
    @Test func aBrighterPartOfTheSceneStaysBrighter() {
        for tone in [
            SceneTone(highlights: -1, shadows: 1), SceneTone(highlights: 1, shadows: -1),
            SceneTone(highlights: -1, shadows: -1), SceneTone(highlights: 1, shadows: 1),
        ] {
            var last = -Double.infinity
            for step in 0 ... 2400 {
                let stops = -14 + Double(step) / 100
                let after = stops + tone.stops(atLuminance: SceneTone.middleGray * pow(2, stops))
                #expect(after > last, "\(tone) at \(stops) stops")
                last = after
            }
        }
    }

    // MARK: - The kernel

    /// Linear pixels as a Core Image picture, in two equal rows.
    private func picture(_ pixels: [SIMD3<Float>]) throws -> CIImage {
        let row: [Float] = pixels.flatMap { [$0.x, $0.y, $0.z, 1] }
        let data = (row + row).withUnsafeBufferPointer { Data(buffer: $0) }
        let space = try #require(CGColorSpace(name: CGColorSpace.linearSRGB))
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(
            width: pixels.count, height: 2, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: pixels.count * 16,
            space: space,
            bitmapInfo: [
                .floatComponents, .byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            ],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
        ))
        return CIImage(cgImage: image)
    }

    private func colors(of pixels: DecodedPixels) -> [SIMD3<Float>] {
        pixels.pixels.withUnsafeBytes { buffer in
            (0 ..< pixels.width * pixels.height).map { index in
                SIMD3(
                    buffer.loadUnaligned(fromByteOffset: index * 16, as: Float.self),
                    buffer.loadUnaligned(fromByteOffset: index * 16 + 4, as: Float.self),
                    buffer.loadUnaligned(fromByteOffset: index * 16 + 8, as: Float.self),
                )
            }
        }
    }

    private func luminance(_ color: SIMD3<Float>) -> Double {
        0.2627 * Double(color.x) + 0.6780 * Double(color.y) + 0.0593 * Double(color.z)
    }

    /// The kernel gives every pixel the stops the curve says for its light once metered and
    /// exposed, and puts the meter's exposure, not the compensation, into the pixels.
    @Test func theKernelAddsTheStopsOfTheCurve() throws {
        try #require(SceneToneKernel.isAvailable)
        var scene: [SIMD3<Float>] = []
        for step in 0 ... 32 {
            let level = Float(SceneTone.middleGray * pow(2, -9 + Double(step) / 2))
            scene.append(SIMD3(level, level, level))
            scene.append(SIMD3(level * 1.6, level * 0.9, level * 0.3))
        }
        let (meteredEV, exposureEV) = (0.7, -0.5)
        let url = URL(fileURLWithPath: "/scene")
        // The scene as Core Image holds it, in the space it works in.
        let plain = try colors(of: ImageLoader.pixels(of: picture(scene), url: url))
        #expect(plain.count == 2 * scene.count && luminance(plain[0]) > 0)
        for tone in [
            SceneTone(highlights: -1, shadows: 1), SceneTone(highlights: 1, shadows: -1),
            SceneTone(highlights: 0.5), SceneTone(shadows: -0.3),
        ] {
            let applied = try SceneToneKernel.apply(tone, to: picture(scene), meteredEV: meteredEV, exposureEV: exposureEV)
            let result = try colors(of: ImageLoader.pixels(of: #require(applied), url: url))
            for (before, after) in zip(plain, result) {
                let metered = luminance(before) * pow(2, meteredEV)
                let gain = pow(2, meteredEV + tone.stops(atLuminance: metered * pow(2, exposureEV)))
                for channel in 0 ..< 3 {
                    let expected = Double(before[channel]) * gain
                    #expect(
                        abs(Double(after[channel]) - expected) <= 0.002 * abs(expected) + 1e-7,
                        "\(tone): \(before) became \(after)",
                    )
                }
            }
        }
    }

    // MARK: - The decoder

    /// A dim evening as a TIFF no larger than the meter reads (so the meter reads the same
    /// picture at every size here): a plain field, a lamp at the top right, a dark corner at the
    /// bottom left.
    private func writeScene() throws -> URL {
        let (width, height) = (240, 160)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let level: Float = if column >= 180, row < 50 {
                    1
                } else if column < 60, row >= 110 {
                    0.0015
                } else {
                    0.04
                }
                let offset = (row * width + column) * 4
                (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3]) = (level, level, level, 1)
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let space = try #require(CGColorSpace(name: CGColorSpace.linearSRGB))
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: width * 16,
            space: space,
            bitmapInfo: [
                .floatComponents, .byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            ],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
        ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-scene-\(UUID().uuidString).tiff")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// The places of the scene the tests look at, in pixels from the top left.
    private enum Place {
        static let field = (column: 100, row: 80)
        static let lamp = (column: 210, row: 25)
        static let corner = (column: 30, row: 135)
    }

    private func level(_ pixels: DecodedPixels, at place: (column: Int, row: Int)) -> Double {
        Double(colors(of: pixels)[place.row * pixels.width + place.column].y)
    }

    @Test func adjustmentsThatLeaveTheSceneAloneAskNothing() async throws {
        #expect(SceneToneRequest(DevelopSettings()) == nil)
        var settings = DevelopSettings(exposureEV: 1)
        settings.sceneTone.shadows = 0.5
        let request = try #require(SceneToneRequest(settings))
        #expect(request.exposureEV == 1 && request.meteringMethod == .centerWeighted)
        settings.autoExposure = false
        #expect(SceneToneRequest(settings)?.meteringMethod == nil)

        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let loaded = try await decoder.decode(settings: DevelopSettings())
        #expect(!loaded.isMetered)
    }

    /// With the meter off the pixels keep their exposure: the corner is lifted, the lamp dimmed,
    /// and the field, a stop and more under middle gray, lifted a little.
    @Test func theDecoderLiftsTheShadowsAndDimsTheHighlights() async throws {
        try #require(SceneToneKernel.isAvailable)
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let plain = try await decoder.pixels(maxDimension: nil, whiteBalance: nil)

        var settings = DevelopSettings(autoExposure: false)
        settings.sceneTone = SceneTone(highlights: -1, shadows: 1)
        let lit = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, sceneTone: SceneToneRequest(settings))
        #expect(!lit.isMetered)
        for place in [Place.field, Place.lamp, Place.corner] {
            let before = level(plain, at: place)
            let expected = before * pow(2, settings.sceneTone.stops(atLuminance: before))
            #expect(abs(level(lit, at: place) - expected) <= 0.003 * expected, "\(place): \(before) became \(level(lit, at: place))")
        }
        #expect(level(lit, at: Place.corner) > 3 * level(plain, at: Place.corner))
        #expect(level(lit, at: Place.lamp) < 0.6 * level(plain, at: Place.lamp))

        // The exposure says where middle gray is: three stops more, and the field is no longer
        // a shadow to lift but a highlight to dim.
        settings.exposureEV = 3
        let exposed = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, sceneTone: SceneToneRequest(settings))
        #expect(level(exposed, at: Place.field) < level(plain, at: Place.field))
    }

    /// With the meter on, the pixels hold the exposure the engine's own meter reads for the photo
    /// as it is without the change of light.
    @Test func withTheMeterOnThePixelsHoldItsExposure() async throws {
        try #require(SceneToneKernel.isAvailable)
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let plain = try await decoder.pixels(maxDimension: nil, whiteBalance: nil)
        let metered = try Double(plain.loaded(from: url, isRaw: false).source.meteredEv(method: "average", input: .rec2020))
        #expect(metered > 0.5, "The evening is dim: the meter adds exposure, and read \(metered).")

        var settings = DevelopSettings(meteringMethod: .average)
        // The decoder says the same to who asks, as the inspector does when the meter is turned off.
        #expect(try await abs(decoder.meteredExposure(settings: settings) - metered) < 1e-6)
        settings.sceneTone.highlights = -1
        let lit = try await decoder.pixels(maxDimension: nil, whiteBalance: nil, sceneTone: SceneToneRequest(settings))
        #expect(lit.isMetered)
        for place in [Place.field, Place.lamp, Place.corner] {
            let before = level(plain, at: place) * pow(2, metered)
            let expected = before * pow(2, settings.sceneTone.stops(atLuminance: before))
            #expect(abs(level(lit, at: place) - expected) <= 0.003 * expected, "\(place): \(before) became \(level(lit, at: place))")
        }
        // Smaller, as for a preview, it holds the same exposure.
        let small = try await decoder.pixels(maxDimension: 120, whiteBalance: nil, sceneTone: SceneToneRequest(settings))
        let smallField = (column: Place.field.column / 2, row: Place.field.row / 2)
        #expect(abs(level(small, at: smallField) - level(lit, at: Place.field)) <= 0.003 * level(lit, at: Place.field))
    }

    // MARK: - The developed photo

    /// The mean of the developed photo around a place, in 8-bit sRGB levels.
    private func developedLevel(_ image: DevelopedImage, at place: (column: Int, row: Int)) throws -> Double {
        let data = try #require(image.cgImage.dataProvider?.data) as Data
        var sum = 0.0
        data.withUnsafeBytes { buffer in
            for row in place.row - 8 ..< place.row + 8 {
                for column in place.column - 8 ..< place.column + 8 {
                    sum += Double(buffer.loadUnaligned(fromByteOffset: (row * image.width + column) * 16 + 4, as: Float.self))
                }
            }
        }
        return sum / 256
    }

    private func develop(
        _ decoder: PhotoDecoder, _ renderer: FilmRenderer, _ change: (inout DevelopSettings) -> Void = { _ in },
    ) async throws -> DevelopedImage {
        var settings = DevelopSettings(meteringMethod: .average)
        settings.grainEnabled = false
        settings.halationEnabled = false
        change(&settings)
        return try await renderer.render(decoder.decode(settings: settings), settings: settings, quality: .full)
    }

    /// The reason the meter's exposure goes into the pixels: dimming the lamp must dim the lamp,
    /// and leave the field as it was. Left to meter the dimmed scene, the engine would find it
    /// darker and expose everything more: measured here, the field twice as bright (0.036 to
    /// 0.073) and the lamp hardly darker (0.68 to 0.67, against 0.55).
    @Test func theMeterDoesNotAnswerTheChangeOfLight() async throws {
        try #require(SceneToneKernel.isAvailable)
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let renderer = try FilmRenderer(dataDirectory: toneDataDirectory, backend: .cpu)

        let plain = try await develop(decoder, renderer)
        let dimmed = try await develop(decoder, renderer) { $0.sceneTone.highlights = -1 }
        let (field, dimmedField) = try (developedLevel(plain, at: Place.field), developedLevel(dimmed, at: Place.field))
        #expect(abs(dimmedField - field) <= 0.01 * field, "The field went from \(field) to \(dimmedField).")
        #expect(try developedLevel(dimmed, at: Place.lamp) < developedLevel(plain, at: Place.lamp) - 0.02)

        // The same light with the engine left to meter it: the field comes out brighter.
        var settings = DevelopSettings(autoExposure: false, meteringMethod: .average)
        settings.grainEnabled = false
        settings.halationEnabled = false
        settings.sceneTone.highlights = -1
        let unmetered = try await decoder.decode(settings: settings)
        settings.autoExposure = true
        let answered = try await renderer.render(unmetered.source, settings: settings, quality: .full)
        #expect(try developedLevel(answered, at: Place.field) > 1.5 * field)
    }

    /// A change of light too small to see develops the photo as it is without it: putting the
    /// meter's exposure into the pixels is what the engine does with it.
    @Test func theSmallestChangeDevelopsThePhotoAsItWas() async throws {
        try #require(SceneToneKernel.isAvailable)
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = try PhotoDecoder(url: url)
        let renderer = try FilmRenderer(dataDirectory: toneDataDirectory, backend: .cpu)
        let plain = try await develop(decoder, renderer) { $0.exposureEV = 0.5 }
        let barely = try await develop(decoder, renderer) {
            $0.exposureEV = 0.5
            $0.sceneTone.shadows = 1e-6
        }
        for place in [Place.field, Place.lamp, Place.corner] {
            let (before, after) = try (developedLevel(plain, at: place), developedLevel(barely, at: place))
            #expect(abs(after - before) <= 0.002, "\(place): \(before) became \(after)")
        }
    }

    // MARK: - The adjustments

    @Test func theLightIsKeptWithTheAdjustmentsAndGoesBackWithTheShot() throws {
        var settings = DevelopSettings()
        settings.sceneTone = SceneTone(highlights: -0.4, shadows: 0.25)
        let read = try JSONDecoder().decode(DevelopSettings.self, from: JSONEncoder().encode(settings))
        #expect(read == settings)
        // Adjustments saved before the app had it leave the scene alone.
        #expect(try JSONDecoder().decode(DevelopSettings.self, from: Data("{}".utf8)).sceneTone.isNeutral)
        #expect(try JSONDecoder().decode(SceneTone.self, from: Data(#"{"shadows":0.5}"#.utf8)) == SceneTone(shadows: 0.5))
        // The engine is not told: the decoder puts the light into the pixels.
        #expect(try !settings.enginePatchJSON().contains("0.25"))

        #expect(!settings.isAtStart(.shot) && settings.isAtStart(.film))
        #expect(settings.resetting(.shot).sceneTone.isNeutral)
        // It is part of the look a recipe gives.
        #expect(Recipe(name: "Evening", from: settings).applied(to: DevelopSettings()).sceneTone == settings.sceneTone)
    }
}
