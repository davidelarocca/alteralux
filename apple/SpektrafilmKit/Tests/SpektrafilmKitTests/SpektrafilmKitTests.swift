import CoreGraphics
import Foundation
import ImageIO
import SpektrafilmEngine
import Testing
import UniformTypeIdentifiers
@testable import SpektrafilmKit

/// The upstream data folder, straight from the git submodule.
private let dataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // SpektrafilmKitTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // SpektrafilmKit
    .deletingLastPathComponent() // apple
    .deletingLastPathComponent() // repository root
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

/// Writes a PNG whose top half is red and bottom half is blue.
private func writeTestChart(width: Int = 96, height: Int = 64) throws -> URL {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ),
    )
    // CoreGraphics' origin is bottom-left: the top half starts at height / 2.
    context.setFillColor(red: 0.8, green: 0.15, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
    context.setFillColor(red: 0.1, green: 0.15, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
    let image = try #require(context.makeImage())

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("spektrafilm-test-\(UUID().uuidString).png")
    let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
    )
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

/// 8-bit sRGB RGBA bytes of `image`, top row first.
private func srgbBytes(of image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
        let context = try #require(
            CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ),
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}

private struct Pixel: CustomStringConvertible {
    var red: Int
    var green: Int
    var blue: Int

    var description: String {
        "(\(red), \(green), \(blue))"
    }
}

/// The pixel at `column`, `row` (from the top left) of RGBA bytes.
private func pixel(_ bytes: [UInt8], width: Int, column: Int, row: Int) -> Pixel {
    let offset = (row * width + column) * 4
    return Pixel(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
}

struct DevelopSettingsTests {
    @Test func defaultPatchIsAcceptedByTheEngine() throws {
        let engine = try Engine(dataDir: dataDirectory.path, backend: .cpu)
        _ = try engine.resolveParamsJson(paramsJson: DevelopSettings().enginePatchJSON())
    }

    @Test func settingsReachTheEngineParameters() throws {
        let engine = try Engine(dataDir: dataDirectory.path, backend: .cpu)
        var settings = DevelopSettings()
        settings.exposureEV = 1.5
        settings.yellowFilterShift = -4
        settings.grainEnabled = false
        settings.scanFilm = true
        settings.sharpenAmount = 0.25
        let resolved = try engine.resolveParamsJson(paramsJson: settings.enginePatchJSON())
        let tree = try #require(
            try JSONSerialization.jsonObject(with: Data(resolved.utf8)) as? [String: Any],
        )
        let camera = try #require(tree["camera"] as? [String: Any])
        let enlarger = try #require(tree["enlarger"] as? [String: Any])
        let film = try #require(tree["film_render"] as? [String: Any])
        let grain = try #require(film["grain"] as? [String: Any])
        let scanner = try #require(tree["scanner"] as? [String: Any])
        let inputOutput = try #require(tree["io"] as? [String: Any])
        #expect(camera["exposure_compensation_ev"] as? Double == 1.5)
        #expect(enlarger["y_filter_shift"] as? Double == -4)
        #expect(grain["active"] as? Bool == false)
        #expect(inputOutput["scan_film"] as? Bool == true)
        #expect((scanner["unsharp_mask"] as? [Double])?.last == 0.25)
    }

    @Test func advancedJSONOverridesAndIsValidated() throws {
        let engine = try Engine(dataDir: dataDirectory.path, backend: .cpu)
        var settings = DevelopSettings()
        settings.advancedJSON = #"{"film_render": {"grain": {"blur": 1.25}}}"#
        let resolved = try engine.resolveParamsJson(paramsJson: settings.enginePatchJSON())
        #expect(resolved.contains("1.25"))

        let unknownKey = DevelopSettings(advancedJSON: #"{"film_render": {"no_such_parameter": 1}}"#)
        #expect(throws: EngineError.self) {
            _ = try engine.resolveParamsJson(paramsJson: unknownKey.enginePatchJSON())
        }
        let notJSON = DevelopSettings(advancedJSON: "not json")
        #expect(throws: (any Error).self) { _ = try notJSON.enginePatchJSON() }
    }

    @Test func settingsRoundTripThroughCodable() throws {
        var settings = DevelopSettings(filmID: "fujifilm_velvia_100", scanFilm: true)
        settings.printExposure = 1.2
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DevelopSettings.self, from: data) == settings)
    }
}

struct PixelBufferTests {
    @Test func enginePixelsBecomeACorrectlyOrientedImage() throws {
        // 1×2 image: top pixel red, bottom pixel blue (display-linear).
        let floats: [Float] = [1, 0, 0, 1, 0, 0, 1, 1]
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let image = try #require(
            FilmRenderer.makeCGImage(pixels: data, width: 1, height: 2, format: .rgbaF32),
        )
        let bytes = try srgbBytes(of: image)
        let top = pixel(bytes, width: 1, column: 0, row: 0)
        let bottom = pixel(bytes, width: 1, column: 0, row: 1)
        #expect(top.red == 255 && top.green == 0 && top.blue == 0, "top: \(top)")
        #expect(bottom.red == 0 && bottom.green == 0 && bottom.blue == 255, "bottom: \(bottom)")
    }

    @Test func wrongBufferSizeIsRejected() {
        #expect(
            FilmRenderer.makeCGImage(pixels: Data(count: 7), width: 1, height: 1, format: .rgbaF32)
                == nil,
        )
    }
}

struct DevelopmentTests {
    @Test func loadsAndDevelopsAnImageKeepingItsOrientation() async throws {
        let url = try writeTestChart()
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try ImageLoader.load(url)
        #expect(loaded.width == 96 && loaded.height == 64)
        #expect(!loaded.isRaw)

        let renderer = try FilmRenderer(dataDirectory: dataDirectory, backend: .cpu)
        var settings = DevelopSettings()
        settings.grainEnabled = false
        let developed = try await renderer.render(loaded, settings: settings, quality: .full)
        #expect(developed.width == 96 && developed.height == 64)

        // Film changes the colors, but red stays warmer than blue and the
        // halves must not be flipped or channel-swapped on the way.
        let bytes = try srgbBytes(of: developed.cgImage)
        let top = pixel(bytes, width: 96, column: 48, row: 8)
        let bottom = pixel(bytes, width: 96, column: 48, row: 56)
        #expect(top.red > top.blue, "top half should stay red: \(top)")
        #expect(bottom.blue > bottom.red, "bottom half should stay blue: \(bottom)")
    }

    @Test func previewIsLimitedToTheRequestedSize() async throws {
        let url = try writeTestChart()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try FilmRenderer(dataDirectory: dataDirectory, backend: .automatic)
        let developed = try await renderer.render(
            ImageLoader.load(url), settings: DevelopSettings(),
            quality: .preview(maxDimension: 48),
        )
        #expect(developed.width == 48 && developed.height == 32)
        print("preview backend: \(renderer.backendName), \(developed.stats.totalMs) ms")
    }

    @Test func loaderCanDownscale() throws {
        let url = try writeTestChart()
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try ImageLoader.load(url, maxDimension: 48)
        #expect(loaded.width == 48 && loaded.height == 32)
    }

    @Test func originalPreviewKeepsOrientationAndSize() throws {
        let url = try writeTestChart()
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(ImageLoader.originalPreview(of: url, maxDimension: 48))
        #expect(image.width == 48 && image.height == 32)
        let bytes = try srgbBytes(of: image)
        let top = pixel(bytes, width: 48, column: 24, row: 4)
        let bottom = pixel(bytes, width: 48, column: 24, row: 28)
        #expect(top.red > top.blue && bottom.blue > bottom.red, "top: \(top), bottom: \(bottom)")
        #expect(ImageLoader.originalPreview(of: URL(fileURLWithPath: "/nonexistent.png"), maxDimension: 48) == nil)
    }

    @Test func unreadableFilesThrow() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing.png")
        #expect(throws: SpektrafilmError.self) { _ = try ImageLoader.load(url) }
    }

    @Test func stocksAreListed() throws {
        let renderer = try FilmRenderer(dataDirectory: dataDirectory, backend: .cpu)
        let stocks = try renderer.stocks()
        #expect(stocks.contains { $0.id == DevelopSettings().filmID && $0.kind == .film })
        #expect(stocks.contains { $0.id == DevelopSettings().paperID && $0.kind == .paper })
    }
}

struct ExportTests {
    private func developedChart() async throws -> (DevelopedImage, URL) {
        let url = try writeTestChart()
        let renderer = try FilmRenderer(dataDirectory: dataDirectory, backend: .cpu)
        let developed = try await renderer.render(
            ImageLoader.load(url), settings: DevelopSettings(), quality: .full,
        )
        return (developed, url)
    }

    private struct ExportedFile {
        var width: Int
        var height: Int
        var profile: String
        var depth: Int
    }

    private func readBack(_ url: URL) throws -> ExportedFile {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
        )
        return ExportedFile(
            width: properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0,
            height: properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0,
            profile: properties[kCGImagePropertyProfileName as String] as? String ?? "",
            depth: properties[kCGImagePropertyDepth as String] as? Int ?? 0,
        )
    }

    @Test(arguments: [ExportOptions.Format.jpeg, .tiff, .png])
    func exportsWithAnEmbeddedProfile(format: ExportOptions.Format) async throws {
        let (developed, original) = try await developedChart()
        defer { try? FileManager.default.removeItem(at: original) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spektrafilm-export-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageExporter.write(
            developed, to: url,
            options: ExportOptions(format: format, colorProfile: .displayP3), originalURL: original,
        )
        let file = try readBack(url)
        #expect(file.width == 96 && file.height == 64)
        #expect(file.profile.contains("P3"), "profile: \(file.profile)")
        #expect(file.depth == (format == .jpeg ? 8 : 16))
    }

    @Test func exportsTenBitHEIC() async throws {
        let (developed, original) = try await developedChart()
        defer { try? FileManager.default.removeItem(at: original) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spektrafilm-export-\(UUID().uuidString).heic")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageExporter.write(developed, to: url, options: ExportOptions(format: .heic))
        let file = try readBack(url)
        #expect(file.width == 96 && file.height == 64)
        #expect(file.profile.contains("sRGB"), "profile: \(file.profile)")
    }
}
