import CoreGraphics
import DesignSystem
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Parent of the suites that draw in a real window (snapshots, screenshots, key presses).
///
/// They run one at a time: each of them spins the main run loop while the window draws, and
/// a test started in parallel would begin inside that wait, with a window of its own.
@MainActor
@Suite(.serialized)
enum WindowedTests {
    /// The upstream data folder, straight from the git submodule.
    static let engineData = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SpektrafilmUITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SpektrafilmKit
        .deletingLastPathComponent() // apple
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

    /// A picture with a different color in every corner, wider than a thumbnail, so cropping,
    /// scaling and orientation show in an image.
    static func testPicture(width: Int = 240, height: Int = 120) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        let half = CGSize(width: width / 2, height: height / 2)
        let quadrants: [(CGPoint, CGColor)] = [
            (CGPoint(x: 0, y: 0), CGColor(srgbRed: 0.8, green: 0.2, blue: 0.2, alpha: 1)),
            (CGPoint(x: half.width, y: 0), CGColor(srgbRed: 0.2, green: 0.7, blue: 0.3, alpha: 1)),
            (CGPoint(x: 0, y: half.height), CGColor(srgbRed: 0.2, green: 0.3, blue: 0.8, alpha: 1)),
            (CGPoint(x: half.width, y: half.height), CGColor(srgbRed: 0.9, green: 0.8, blue: 0.2, alpha: 1)),
        ]
        for (origin, color) in quadrants {
            context.setFillColor(color)
            context.fill(CGRect(origin: origin, size: half))
        }
        return context.makeImage()
    }

    /// Writes `count` test pictures as PNG files into a new temporary folder and returns their
    /// URLs. The caller removes the folder (the parent of the files).
    static func writeTestPictures(count: Int) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("spektrafilm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let picture = try #require(testPicture())
        return try (1 ... count).map { index in
            let url = folder.appendingPathComponent("Picture \(index).png")
            let destination = try #require(
                CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
            )
            CGImageDestinationAddImage(destination, picture, nil)
            try #require(CGImageDestinationFinalize(destination))
            return url
        }
    }
}

/// A `ParameterSlider` with a value of its own, as a screen holds it. `onChange` reports the
/// value out: a `Binding(get:set:)` over a plain variable keeps the value SwiftUI read last.
struct SliderHost: View {
    private let title: LocalizedStringKey
    private let range: ClosedRange<Double>
    private let step: Double
    private let defaultValue: Double
    private let fractionDigits: Int
    private let showsSign: Bool
    private let onChange: (Double) -> Void
    @State private var value: Double

    init(
        _ title: LocalizedStringKey,
        value: Double,
        in range: ClosedRange<Double> = -5 ... 5,
        step: Double = 0.1,
        defaultValue: Double = 0,
        fractionDigits: Int = 1,
        showsSign: Bool = true,
        onChange: @escaping (Double) -> Void = { _ in },
    ) {
        self.title = title
        _value = State(initialValue: value)
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.fractionDigits = fractionDigits
        self.showsSign = showsSign
        self.onChange = onChange
    }

    var body: some View {
        ParameterSlider(
            title, value: $value, in: range, step: step, defaultValue: defaultValue,
            fractionDigits: fractionDigits, showsSign: showsSign,
        )
        .padding(Spacing.m)
        .onChange(of: value) { _, new in onChange(new) }
    }
}
