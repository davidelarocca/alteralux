import CoreImage
import Foundation
import Testing
@testable import AlteraluxKit

/// How the camera's corrections are combined with Apple's decoder and lensfun (ADR 0015), and the
/// zoom that fills the frame.
struct CameraLensCorrectionTests {
    static let size = SIMD2(6000, 4000)

    static func sony() throws -> CameraLensData {
        try #require(SonyLensData.read(CameraLensDataTests.arw()))
    }

    /// A lensfun profile with barrel distortion and vignetting, centered on a 6000 × 4000 photo.
    static let lensfun = LensCorrection(
        lensName: "Profile", distortionModel: .poly3, distortionTerms: SIMD3(-0.02, 0, 0), distortionUnit: 2000,
        center: SIMD2(2999.5, 1999.5), tcaModel: .none, tcaRed: SIMD3(1, 0, 0), tcaBlue: SIMD3(1, 0, 0),
        vignettingTerms: SIMD3(-0.3, 0, 0), vignettingUnit: 3605.55, scale: 1,
    )

    @Test func withoutAppleTheCameraCorrectsEverything() throws {
        let correction = try #require(CameraLensCorrection.combining(
            camera: Self.sony(), lensfun: Self.lensfun, appleCorrects: false, lensName: "Viltrox", size: Self.size,
        ))
        #expect(correction.geometrySource == .camera && correction.vignettingSource == .camera)
        #expect(correction.movesPixels)
        #expect(correction.lensName == "Viltrox")
        #expect(abs(correction.unit - 3605.55) < 0.01)
    }

    @Test func whereAppleCorrectsTheGeometryOnlyTheVignettingIsLifted() throws {
        let correction = try #require(CameraLensCorrection.combining(
            camera: Self.sony(), lensfun: nil, appleCorrects: true, lensName: "", size: Self.size,
        ))
        #expect(correction.geometrySource == .apple && correction.vignettingSource == .camera)
        #expect(!correction.movesPixels)
        let corner = SIMD2(0.0, 0.0)
        #expect(correction.sourcePoint(ofCorrected: corner, channel: 1) == corner)
        // Read where the camera's curve says the pixel was, a little further out than the corner.
        let sony = try Self.sony()
        let expected = 1 / (sony.vignetting?.value(at: 1 / correction.scale * 1.008) ?? 1)
        #expect(abs(correction.vignettingGain(at: corner) - expected) / expected < 0.03)
    }

    @Test func appleLiftsNikonsVignettingItself() throws {
        let nikon = try #require(NikonLensData.read(CameraLensDataTests.nef()))
        #expect(CameraLensCorrection.combining(camera: nikon, lensfun: nil, appleCorrects: true, lensName: "", size: Self.size) == nil)
        let olympus = try #require(OlympusLensData.read(CameraLensDataTests.orf()))
        #expect(CameraLensCorrection.combining(camera: olympus, lensfun: nil, appleCorrects: true, lensName: "", size: Self.size) == nil)
        // Where Apple's decoder does not know the lens, Nikon's own numbers do it all.
        let alone = try #require(CameraLensCorrection.combining(camera: nikon, lensfun: nil, appleCorrects: false, lensName: "", size: Self.size))
        #expect(alone.geometrySource == .camera && alone.vignettingSource == .camera)
    }

    @Test func whatTheCameraLeavesOutComesFromLensfun() throws {
        let olympus = try #require(OlympusLensData.read(CameraLensDataTests.orf()))
        let withLight = try #require(CameraLensCorrection.combining(
            camera: olympus, lensfun: Self.lensfun, appleCorrects: false, lensName: "", size: Self.size,
        ))
        #expect(withLight.geometrySource == .camera && withLight.vignettingSource == .lensfun)
        let corner = SIMD2(0.0, 0.0)
        #expect(abs(withLight.vignettingGain(at: corner) - Self.lensfun.vignettingGain(at: corner)) < 1e-3)

        let lightOnly = try #require(CameraLensData(maker: .sony, geometry: nil, vignetting: Self.sony().vignetting))
        let withGeometry = try #require(CameraLensCorrection.combining(
            camera: lightOnly, lensfun: Self.lensfun, appleCorrects: false, lensName: "", size: Self.size,
        ))
        #expect(withGeometry.geometrySource == .lensfun && withGeometry.vignettingSource == .camera)
        // The profile's own mapping, its zoom aside.
        let along = SIMD2(6000.0, 4000.0) / (2 * withGeometry.unit) * 0.8 * withGeometry.unit
        let shot = Self.lensfun.sourcePoint(ofCorrected: Self.lensfun.center + along, channel: 1) - Self.lensfun.center
        let ratio = (shot.x * shot.x + shot.y * shot.y).squareRoot() / (0.8 * withGeometry.unit)
        #expect(abs(withGeometry.green.value(at: 0.8) - ratio) < 1e-4)
    }

    @Test func noCameraDataLeavesItToTheOthers() {
        #expect(CameraLensCorrection.combining(camera: nil, lensfun: Self.lensfun, appleCorrects: false, lensName: "", size: Self.size) == nil)
    }

    /// The corrected picture's edge comes from inside the photo, and only just: no empty corners,
    /// and no more zoom than needed.
    @Test(arguments: [false, true])
    func theCorrectedPictureFillsTheFrame(stronger: Bool) throws {
        let sony = try Self.sony()
        let geometry = try #require(sony.geometry)
        let green = stronger ? RadialCurve(sampling: { 1 + (geometry.green.value(at: $0) - 1) * 6 }) : geometry.green
        let correction = try #require(CameraLensCorrection(
            lensName: "", geometry: .init(red: geometry.red, green: green, blue: geometry.blue), geometrySource: .camera,
            light: nil, vignettingSource: nil, width: 6000, height: 4000,
        ))
        var reach = 0.0
        for step in 0 ... 200 {
            let along = Double(step) / 200
            for point in [
                SIMD2(along * 5999, 0), SIMD2(along * 5999, 3999), SIMD2(0, along * 3999), SIMD2(5999, along * 3999),
            ] {
                for channel in 0 ..< 3 {
                    let source = correction.sourcePoint(ofCorrected: point, channel: channel)
                    let excess = max(
                        abs(source.x - correction.center.x) / correction.center.x,
                        abs(source.y - correction.center.y) / correction.center.y,
                    )
                    reach = max(reach, excess)
                }
            }
        }
        #expect(reach <= 1)
        #expect(reach > 0.997)
        #expect(correction.scale > 1)
    }
}

/// The kernel for the camera's curves, on a picture whose pixels say where they are (see
/// `LensWarpTests`).
struct CameraLensWarpTests {
    private let width = 300
    private let height = 200
    private static let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let context = CIContext(options: [
        .workingColorSpace: space, .workingFormat: NSNumber(value: CIFormat.RGBAf.rawValue),
    ])

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
        return CIImage(
            bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: Self.space,
        )
    }

    private func pixel(of image: CIImage, at point: SIMD2<Int>) -> SIMD4<Float> {
        var value = [Float](repeating: 0, count: 4)
        let bounds = CGRect(x: point.x, y: height - 1 - point.y, width: 1, height: 1)
        Self.context.render(image, toBitmap: &value, rowBytes: 16, bounds: bounds, format: .RGBAf, colorSpace: Self.space)
        return SIMD4(value[0], value[1], value[2], value[3])
    }

    private var size: CGSize {
        CGSize(width: width, height: height)
    }

    /// A strong, wavy distortion with fringes, and no vignetting.
    private func wavy() throws -> CameraLensCorrection {
        let green = RadialCurve(sampling: { 1 + 0.04 * sin($0 * 6) })
        let red = RadialCurve(sampling: { (1 + 0.04 * sin($0 * 6)) * 1.003 })
        let blue = RadialCurve(sampling: { (1 + 0.04 * sin($0 * 6)) * 0.997 })
        return try #require(CameraLensCorrection(
            lensName: "", geometry: .init(red: red, green: green, blue: blue), geometrySource: .camera,
            light: nil, vignettingSource: nil, width: width, height: height,
        ))
    }

    @Test func theKernelCompiles() {
        #expect(LensWarp.isAvailable)
    }

    @Test func theKernelFollowsTheReference() throws {
        let correction = try wavy()
        let corrected = LensWarp.apply(correction, to: positions(), fullSize: size)
        for point in [SIMD2(10, 12), SIMD2(150, 100), SIMD2(280, 30), SIMD2(70, 190), SIMD2(299, 199), SIMD2(200, 60)] {
            let value = pixel(of: corrected, at: point)
            let here = SIMD2(Double(point.x), Double(point.y))
            // Red holds x and is sampled through the red curve; green holds y, through green's.
            let red = correction.sourcePoint(ofCorrected: here, channel: 0)
            let green = correction.sourcePoint(ofCorrected: here, channel: 1)
            let sampled = SIMD2(Double(value.x) * Double(width) - 0.5, Double(value.y) * Double(height) - 0.5)
            #expect(abs(sampled.x - red.x) < 0.05, "at \(point): x \(sampled.x), expected \(red.x)")
            #expect(abs(sampled.y - green.y) < 0.05, "at \(point): y \(sampled.y), expected \(green.y)")
        }
    }

    @Test func theKernelLiftsTheCorners() throws {
        let light = RadialCurve(sampling: { 1 - 0.5 * $0 * $0 })
        let correction = try #require(CameraLensCorrection(
            lensName: "", geometry: nil, geometrySource: .apple, light: light, vignettingSource: .camera,
            width: width, height: height,
        ))
        let corrected = LensWarp.apply(correction, to: positions(blue: 0.4), fullSize: size)
        #expect(abs(pixel(of: corrected, at: SIMD2(150, 100)).z - 0.4) < 0.001)
        for point in [SIMD2(0, 0), SIMD2(299, 120), SIMD2(40, 180)] {
            let here = SIMD2(Double(point.x), Double(point.y))
            let expected = 0.4 * correction.vignettingGain(at: here)
            let value = pixel(of: corrected, at: point)
            #expect(abs(Double(value.z) - expected) < 0.002, "at \(point): \(value.z), expected \(expected)")
            // The pixels stay where they are: red, lifted by the same gain, still says so.
            let x = Double(value.x) / correction.vignettingGain(at: here) * Double(width) - 0.5
            #expect(abs(x - here.x) < 0.05, "at \(point): x \(x)")
        }
    }

    @Test func aReducedCopyIsCorrectedLikeTheWholePhoto() throws {
        let correction = try wavy()
        let whole = LensWarp.apply(correction, to: positions(), fullSize: size)
        let half = LensWarp.apply(
            correction, to: positions().transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)), fullSize: size,
        )
        var value = [Float](repeating: 0, count: 4)
        Self.context.render(
            half, toBitmap: &value, rowBytes: 16, bounds: CGRect(x: 60, y: 100 - 1 - 20, width: 1, height: 1),
            format: .RGBAf, colorSpace: Self.space,
        )
        let reference = pixel(of: whole, at: SIMD2(121, 41))
        #expect(abs(value[0] - reference.x) < 1.5 / Float(width) && abs(value[1] - reference.y) < 1.5 / Float(height))
    }
}
