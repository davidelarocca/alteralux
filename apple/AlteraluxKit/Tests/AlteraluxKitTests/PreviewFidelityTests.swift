import AlteraluxEngine
import CoreGraphics
import Foundation
import Testing
@testable import AlteraluxKit

/// The upstream data folder, straight from the git submodule.
private let fidelityDataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxKitTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // AlteraluxKit
    .deletingLastPathComponent() // apple
    .deletingLastPathComponent() // repository root
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

/// How close a preview is to the exported photo seen at the same size.
///
/// The app develops a preview from the photo decoded small (ADR 0007), and the engine sizes
/// grain and halation from the film format, so a pixel of a preview stands for more film. What
/// the engine cannot resolve at a size it loses, and the grain is softened by a blur given in
/// pixels (`grain.blur`, 0.65), which takes as much from a small picture as from a large one,
/// where it no longer shows once the picture is seen smaller. These tests keep what was
/// measured on 2026-11-24 from getting worse: a submodule update or a smaller preview that
/// moves the numbers fails here and is looked at, not found by eye.
///
/// The pictures are strips sixteen times wider than tall: the engine takes the size of a pixel
/// from the long side, so a strip costs a sixteenth of the whole frame.
struct PreviewFidelityTests {
    /// The long side of a 24-megapixel photo, about: what an export is.
    private static let exportSide = 6144
    /// The preview shown once the settings stay still (`PreviewSize.standard` in AlteraluxUI).
    private static let standardSide = 2048
    /// The preview shown while a control moves.
    private static let lighterSide = 1024

    /// Display-linear RGBA pixels, top row first.
    private struct Frame {
        let width: Int
        let height: Int
        let pixels: [Float]

        /// One channel of the frame seen `factor` times smaller: each value the mean of a block.
        func channel(_ channel: Int, reducedBy factor: Int = 1) -> [Double] {
            let (smallWidth, smallHeight) = (width / factor, height / factor)
            var reduced = [Double](repeating: 0, count: smallWidth * smallHeight)
            pixels.withUnsafeBufferPointer { pixels in
                reduced.withUnsafeMutableBufferPointer { reduced in
                    for row in 0 ..< smallHeight * factor {
                        let (source, target) = (row * width * 4 + channel, row / factor * smallWidth)
                        for column in 0 ..< smallWidth * factor {
                            reduced[target + column / factor] += Double(pixels[source + column * 4])
                        }
                    }
                    for index in reduced.indices {
                        reduced[index] /= Double(factor * factor)
                    }
                }
            }
            return reduced
        }
    }

    /// The mean of `values`.
    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    /// How much `values` vary around their mean.
    private static func deviation(_ values: [Double]) -> Double {
        let mean = mean(values)
        return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
    }

    /// A strip of middle gray, `side` pixels wide, with a bar across its middle 6.5 stops
    /// brighter when `lit`: a lamp in the evening.
    private static func strip(side: Int, lit: Bool) throws -> SourceImage {
        let height = side / 16
        var pixels = [Float](repeating: 0.18, count: side * height * 3)
        if lit {
            let bar = side / 16
            for row in 0 ..< height {
                for column in (side - bar) / 2 ..< (side + bar) / 2 {
                    for channel in 0 ..< 3 {
                        pixels[(row * side + column) * 3 + channel] = 16
                    }
                }
            }
        }
        return try SourceImage.fromFloats(pixels, width: side, height: height, channels: 3)
    }

    /// The strip developed whole at `side` pixels, as the app develops a photo decoded at that
    /// size, with the meter off so the bar does not darken the rest.
    private static func developed(
        _ renderer: FilmRenderer, side: Int, lit: Bool, _ change: (inout DevelopSettings) -> Void,
    ) async throws -> Frame {
        var settings = DevelopSettings()
        settings.autoExposure = false
        change(&settings)
        let image = try await renderer.render(strip(side: side, lit: lit), settings: settings, quality: .full)
        let data = try #require(image.cgImage.dataProvider?.data) as Data
        return Frame(
            width: image.width, height: image.height,
            pixels: data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) },
        )
    }

    /// Plain gray developed at `side` pixels with its grain and no halation.
    private static func grainy(_ renderer: FilmRenderer, side: Int) async throws -> Frame {
        try await developed(renderer, side: side, lit: false) { $0.halationEnabled = false }
    }

    /// The red light the halation adds around the bar at `side` pixels, per unit of picture:
    /// the same at every size if the glow keeps its place on the film.
    private static func halation(_ renderer: FilmRenderer, side: Int) async throws -> Double {
        let with = try await developed(renderer, side: side, lit: true) { $0.grainEnabled = false }
        let without = try await developed(renderer, side: side, lit: true) {
            $0.grainEnabled = false
            $0.halationEnabled = false
        }
        return mean(with.channel(0)) - mean(without.channel(0))
    }

    /// Measured on 2026-11-24 (Apple M5, GPU; the CPU gives the same): a preview shown pixel for
    /// pixel has about two thirds of the grain of the export seen at that size, 0.66 for the
    /// standard preview and 0.62 for the lighter one; the standard preview shown at half its
    /// size, 0.87. The 100% view is the export's own render.
    @Test func aPreviewShowsTwoThirdsOfTheExportsGrain() async throws {
        let renderer = try FilmRenderer(dataDirectory: fidelityDataDirectory, backend: .automatic)
        let export = try await Self.grainy(renderer, side: Self.exportSide)
        let standard = try await Self.grainy(renderer, side: Self.standardSide)
        let lighter = try await Self.grainy(renderer, side: Self.lighterSide)
        // The strength of the grain of `frame` seen `side` pixels wide.
        func grain(_ frame: Frame, at side: Int) -> Double {
            Self.deviation(frame.channel(1, reducedBy: frame.width / side))
        }
        #expect(grain(export, at: Self.lighterSide) > 0.005, "No grain to compare.")

        let standardShare = grain(standard, at: Self.standardSide) / grain(export, at: Self.standardSide)
        #expect((0.55 ... 1.05).contains(standardShare), "The standard preview has \(standardShare) of the export's grain.")
        let lighterShare = grain(lighter, at: Self.lighterSide) / grain(export, at: Self.lighterSide)
        #expect((0.55 ... 1.05).contains(lighterShare), "The lighter preview has \(lighterShare) of the export's grain.")
        // Shown smaller than it is, as in a window narrower than the preview, it is closer.
        let halvedShare = grain(standard, at: Self.lighterSide) / grain(export, at: Self.lighterSide)
        #expect((0.8 ... 1.05).contains(halvedShare), "Halved, the standard preview has \(halvedShare).")
    }

    /// Measured on 2026-11-24 (Apple M5, GPU): the standard preview has 0.96 of the export's red
    /// halation, the lighter one 0.87. On the CPU, 0.97 and 0.92.
    @Test func aPreviewShowsTheExportsHalation() async throws {
        let renderer = try FilmRenderer(dataDirectory: fidelityDataDirectory, backend: .automatic)
        let export = try await Self.halation(renderer, side: Self.exportSide)
        let standard = try await Self.halation(renderer, side: Self.standardSide)
        let lighter = try await Self.halation(renderer, side: Self.lighterSide)
        #expect(export > 0.001, "No halation to compare: \(export)")

        let standardShare = standard / export
        #expect((0.85 ... 1.15).contains(standardShare), "The standard preview has \(standardShare) of the export's halation.")
        let lighterShare = lighter / export
        #expect((0.7 ... 1.15).contains(lighterShare), "The lighter preview has \(lighterShare) of the export's halation.")
    }
}
