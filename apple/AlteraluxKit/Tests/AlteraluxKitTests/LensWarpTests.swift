import CoreImage
import Foundation
import Testing
@testable import AlteraluxKit

/// The lens kernel, on pictures whose pixels say where they are: red is x and green is y, as
/// fractions of the width and height, measured from the top left. After the correction, each pixel
/// tells where in the photo it was taken from.
struct LensWarpTests {
    private let width = 300
    private let height = 200
    private static let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let context = CIContext(options: [
        .workingColorSpace: space, .workingFormat: NSNumber(value: CIFormat.RGBAf.rawValue),
    ])

    /// A picture whose red and green say where each pixel is; blue is `blue` everywhere.
    private func positions(blue: Float = 0.5) -> CIImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let index = (row * width + column) * 4
                pixels[index] = (Float(column) + 0.5) / Float(width)
                pixels[index + 1] = (Float(row) + 0.5) / Float(height)
                pixels[index + 2] = blue
                pixels[index + 3] = 1
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        // Rows go from the top: Core Image's bitmaps do too.
        return CIImage(
            bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: Self.space,
        )
    }

    /// The pixel at `point` (from the top left) of `image`.
    private func pixel(of image: CIImage, at point: SIMD2<Int>) -> SIMD4<Float> {
        var value = [Float](repeating: 0, count: 4)
        let bounds = CGRect(x: point.x, y: height - 1 - point.y, width: 1, height: 1)
        Self.context.render(image, toBitmap: &value, rowBytes: 16, bounds: bounds, format: .RGBAf, colorSpace: Self.space)
        return SIMD4(value[0], value[1], value[2], value[3])
    }

    /// No correction at all, for a picture of `width` × `height`, centered.
    private func plain() -> LensCorrection {
        LensCorrection(
            lensName: "Test", distortionModel: .none, distortionTerms: .zero, distortionUnit: 100,
            center: SIMD2(Double(width - 1) / 2, Double(height - 1) / 2), tcaModel: .none, tcaRed: .zero,
            tcaBlue: .zero, vignettingTerms: .zero, vignettingUnit: 180, scale: 1,
        )
    }

    private var size: CGSize {
        CGSize(width: width, height: height)
    }

    /// Where the pixel at `point` of `corrected` was taken from, as red and green tell, in the
    /// correction's pixels (the first pixel's center at the origin).
    private func source(in corrected: CIImage, at point: SIMD2<Int>) -> SIMD2<Double> {
        let value = pixel(of: corrected, at: point)
        return SIMD2(Double(value.x) * Double(width) - 0.5, Double(value.y) * Double(height) - 0.5)
    }

    @Test func theKernelCompiles() {
        #expect(LensWarp.isAvailable)
    }

    @Test func noCorrectionLeavesThePicture() {
        let image = positions()
        let corrected = LensWarp.apply(plain(), to: image, fullSize: size)
        for point in [SIMD2(0, 0), SIMD2(37, 150), SIMD2(299, 199)] {
            let before = pixel(of: image, at: point)
            let after = pixel(of: corrected, at: point)
            #expect(abs(before.x - after.x) < 1e-4 && abs(before.y - after.y) < 1e-4, "\(point): \(before) \(after)")
        }
    }

    /// Every model, scaled, with fringing: the kernel samples green where the Swift reference says.
    @Test(arguments: [LensDistortionModel.poly3, .poly5, .ptlens])
    func theKernelFollowsTheReference(model: LensDistortionModel) {
        let terms: SIMD3<Double> = switch model {
        case .none: .zero
        case .poly3: SIMD3(-0.05, 0, 0)
        case .poly5: SIMD3(-0.04, 0.01, 0)
        case .ptlens: SIMD3(0.01, -0.03, 0.02)
        }
        let correction = LensCorrection(
            lensName: "Test", distortionModel: model, distortionTerms: terms, distortionUnit: 110,
            center: SIMD2(151, 98), tcaModel: .poly3, tcaRed: SIMD3(1.002, 0.001, 0), tcaBlue: SIMD3(0.998, 0, 0),
            vignettingTerms: .zero, vignettingUnit: 180, scale: 1.06,
        )
        let corrected = LensWarp.apply(correction, to: positions(), fullSize: size)
        for point in [SIMD2(10, 12), SIMD2(150, 100), SIMD2(280, 30), SIMD2(70, 190), SIMD2(299, 199)] {
            let expected = correction.sourcePoint(ofCorrected: SIMD2(Double(point.x), Double(point.y)), channel: 1)
            let sampled = source(in: corrected, at: point)
            // Red holds x, and red is taken a little further out: compare y alone for green, and
            // x through the red channel's own reference.
            let expectedRed = correction.sourcePoint(ofCorrected: SIMD2(Double(point.x), Double(point.y)), channel: 0)
            #expect(abs(sampled.x - expectedRed.x) < 0.05, "\(model) at \(point): x \(sampled.x), expected \(expectedRed.x)")
            #expect(abs(sampled.y - expected.y) < 0.05, "\(model) at \(point): y \(sampled.y), expected \(expected.y)")
        }
    }

    @Test func vignettingBrightensTheCorners() {
        var correction = plain()
        correction = LensCorrection(
            lensName: "Test", distortionModel: .none, distortionTerms: .zero, distortionUnit: 100,
            center: correction.center, tcaModel: .none, tcaRed: .zero, tcaBlue: .zero,
            vignettingTerms: SIMD3(-0.3, 0, 0), vignettingUnit: 180, scale: 1,
        )
        let corrected = LensWarp.apply(correction, to: positions(blue: 0.4), fullSize: size)
        let middle = pixel(of: corrected, at: SIMD2(150, 100))
        let corner = pixel(of: corrected, at: SIMD2(0, 0))
        #expect(abs(middle.z - 0.4) < 0.001)
        let expected = 0.4 * correction.vignettingGain(at: SIMD2(0, 0))
        #expect(abs(Double(corner.z) - expected) < 0.002, "corner: \(corner.z), expected \(expected)")
    }

    @Test func aReducedCopyIsCorrectedLikeTheWholePhoto() {
        let correction = LensCorrection(
            lensName: "Test", distortionModel: .poly3, distortionTerms: SIMD3(0.1, 0, 0), distortionUnit: 100,
            center: plain().center, tcaModel: .none, tcaRed: .zero, tcaBlue: .zero,
            vignettingTerms: .zero, vignettingUnit: 180, scale: 1,
        )
        let whole = LensWarp.apply(correction, to: positions(), fullSize: size)
        let half = LensWarp.apply(
            correction, to: positions().transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)), fullSize: size,
        )
        // The pixel at (60, 20) of the half copy covers (120...122, 40...42) of the whole photo.
        var value = [Float](repeating: 0, count: 4)
        Self.context.render(
            half, toBitmap: &value, rowBytes: 16, bounds: CGRect(x: 60, y: 100 - 1 - 20, width: 1, height: 1),
            format: .RGBAf, colorSpace: Self.space,
        )
        let reference = pixel(of: whole, at: SIMD2(121, 41))
        #expect(abs(value[0] - reference.x) < 1.5 / Float(width) && abs(value[1] - reference.y) < 1.5 / Float(height))
    }
}
