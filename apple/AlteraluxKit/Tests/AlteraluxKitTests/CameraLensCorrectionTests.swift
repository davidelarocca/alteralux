import CoreImage
import Foundation
import Testing
@testable import AlteraluxKit

/// The corrections a Sony camera records in its RAW: read from the file, turned into curves, and
/// applied by the kernel as the Swift reference says.
struct CameraLensCorrectionTests {
    /// The numbers a Sony ZV-E10 recorded with a Viltrox 56mm F1.7 at f/1.7: eleven knots each.
    static let distortion = [11, 2, 3, 6, 13, 23, 37, 53, 71, 90, 111, 131, 0, 0, 0, 0, 0]
    static let aberration = [22] + [Int](repeating: -256, count: 22) + [Int](repeating: 0, count: 10)
    static let vignetting = [11, 0, 352, 1152, 2304, 3712, 5280, 6880, 8448, 9888, 11200, 12288, 0, 0, 0, 0, 0]

    /// A TIFF laid out as an ARW: a main directory naming the maker and pointing at a raw one
    /// that holds the three tags as signed 16-bit numbers.
    static func arw(
        maker: String = "SONY",
        distortion: [Int] = distortion,
        aberration: [Int] = aberration,
        vignetting: [Int] = vignetting,
        bigEndian: Bool = false,
    ) -> Data {
        var bytes: [UInt8] = []
        func put(_ value: Int, _ size: Int) {
            let unsigned = value < 0 ? value + (1 << (size * 8)) : value
            let ordered = (0 ..< size).map { UInt8((unsigned >> ($0 * 8)) & 0xFF) }
            bytes += bigEndian ? ordered.reversed() : ordered
        }
        bytes += bigEndian ? [0x4D, 0x4D] : [0x49, 0x49]
        put(42, 2)
        put(8, 4)
        // Main directory at 8: two entries, Make and SubIFDs.
        let makeBytes = Array(maker.utf8) + [0]
        let mainEnd = 8 + 2 + 2 * 12 + 4
        let rawDirectory = mainEnd + makeBytes.count + (makeBytes.count % 2)
        put(2, 2)
        put(0x010F, 2); put(2, 2); put(makeBytes.count, 4); put(mainEnd, 4)
        put(0x014A, 2); put(4, 2); put(1, 4); put(rawDirectory, 4)
        put(0, 4)
        bytes += makeBytes
        if makeBytes.count % 2 == 1 {
            bytes.append(0)
        }
        // Raw directory: three entries pointing past it.
        var valuesAt = rawDirectory + 2 + 3 * 12 + 4
        put(3, 2)
        var payload: [[Int]] = []
        for (tag, values) in [(0x7032, vignetting), (0x7035, aberration), (0x7037, distortion)] {
            put(tag, 2); put(8, 2); put(values.count, 4); put(valuesAt, 4)
            valuesAt += values.count * 2
            payload.append(values)
        }
        put(0, 4)
        for values in payload {
            for value in values {
                put(value, 2)
            }
        }
        return Data(bytes)
    }

    @Test func theCurvesAreReadAsDarktableReadsThem() throws {
        let curves = try #require(SonyLensData.curves(in: Self.arw()))
        #expect(curves.green.count == 11)
        #expect(curves.green[0] == 1 + 2.0 / 16384)
        #expect(curves.green[10] == 1 + 131.0 / 16384)
        #expect(abs(curves.red[3] - curves.green[3] * (1 - 256.0 / 2_097_152)) < 1e-15)
        #expect(curves.vignetting[0] == 1)
        let kept = pow(2, 0.5 - pow(2, 12288.0 / 8192 - 1))
        #expect(abs(curves.vignetting[10] - kept * kept) < 1e-12)
        // About -1.8 EV at the last knot, past the corner.
        #expect(abs(log2(curves.vignetting[10]) + 1.83) < 0.01)
    }

    @Test func aBigEndianFileReadsTheSame() {
        #expect(SonyLensData.curves(in: Self.arw(bigEndian: true)) == SonyLensData.curves(in: Self.arw()))
    }

    @Test func otherMakersAndMalformedTagsAreLeftAlone() {
        #expect(SonyLensData.curves(in: Self.arw(maker: "FUJIFILM")) == nil)
        #expect(SonyLensData.curves(in: Self.arw(aberration: [20] + [Int](repeating: 0, count: 20))) == nil)
        #expect(SonyLensData.curves(in: Self.arw(vignetting: [16] + [Int](repeating: 0, count: 16))) == nil)
        #expect(SonyLensData.curves(in: Self.arw(distortion: [17] + [Int](repeating: 1, count: 17))) == nil)
        #expect(SonyLensData.curves(in: Data("not a tiff".utf8)) == nil)
        #expect(SonyLensData.curves(in: Data(Self.arw().prefix(60))) == nil)
    }

    @Test func aCameraThatRecordedNothingIsNotCorrected() {
        let zeros = [11] + [Int](repeating: 0, count: 16)
        let noAberration = [22] + [Int](repeating: 0, count: 32)
        #expect(SonyLensData.curves(in: Self.arw(distortion: zeros, aberration: noAberration, vignetting: zeros)) == nil)
    }

    @Test func onlyRawFilesFromSonyAreRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let arw = folder.appendingPathComponent("photo.ARW")
        let tiff = folder.appendingPathComponent("photo.tif")
        try Self.arw().write(to: arw)
        try Self.arw().write(to: tiff)
        let correction = try #require(SonyLensData.correction(for: arw, lensName: "Viltrox 56mm F1.7 E", width: 6000, height: 4000))
        #expect(correction.lensName == "Viltrox 56mm F1.7 E")
        #expect(correction.center == SIMD2(2999.5, 1999.5))
        #expect(abs(correction.unit - 3605.55) < 0.01)
        #expect(SonyLensData.correction(for: tiff, lensName: "", width: 6000, height: 4000) == nil)
    }

    @Test func theCurveRunsStraightBetweenItsKnots() {
        // Four knots at 1/6, 1/2, 5/6 and 7/6 of the half diagonal.
        let curve = [1.0, 2.0, 4.0, 8.0]
        #expect(CameraLensCorrection.value(of: curve, at: 0) == 1)
        #expect(CameraLensCorrection.value(of: curve, at: 1.0 / 6) == 1)
        #expect(abs(CameraLensCorrection.value(of: curve, at: 1.0 / 3) - 1.5) < 1e-12)
        #expect(abs(CameraLensCorrection.value(of: curve, at: 0.5) - 2) < 1e-12)
        #expect(abs(CameraLensCorrection.value(of: curve, at: 1) - 6) < 1e-12)
        #expect(CameraLensCorrection.value(of: curve, at: 2) == 8)
    }

    /// The corrected picture's edge comes from inside the photo, and only just: no empty corners,
    /// and no more zoom than needed.
    @Test(arguments: [false, true])
    func theCorrectedPictureFillsTheFrame(bigger: Bool) throws {
        let curves = try #require(SonyLensData.curves(in: Self.arw()))
        let green = bigger ? curves.green.map { 1 + ($0 - 1) * 6 } : curves.green
        let correction = try #require(CameraLensCorrection(
            lensName: "Test", green: green, red: curves.red, blue: curves.blue, vignetting: curves.vignetting,
            width: 6000, height: 4000,
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

    @Test func vignettingIsLiftedWhereTheLensDarkens() throws {
        let curves = try #require(SonyLensData.curves(in: Self.arw()))
        let correction = try #require(CameraLensCorrection(
            lensName: "Test", green: curves.green, red: curves.red, blue: curves.blue, vignetting: curves.vignetting,
            width: 6000, height: 4000,
        ))
        #expect(correction.vignettingGain(at: correction.center) == 1)
        let corner = correction.vignettingGain(at: .zero)
        // Between knots 9 and 10, about 1.7 EV brighter.
        #expect(corner > 3 && corner < 3.5, "\(corner)")
    }

    @Test func curvesOfDifferentLengthsAreRefused() {
        #expect(CameraLensCorrection(
            lensName: "", green: [1, 1], red: [1, 1], blue: [1, 1], vignetting: [1], width: 10, height: 10,
        ) == nil)
        #expect(CameraLensCorrection(
            lensName: "", green: [1], red: [1], blue: [1], vignetting: [1], width: 10, height: 10,
        ) == nil)
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

    /// A strong, wavy distortion with fringes, over thirteen knots, and no vignetting.
    private func wavy() throws -> CameraLensCorrection {
        let green = (0 ..< 13).map { 1 + 0.04 * sin(Double($0) / 2) }
        return try #require(CameraLensCorrection(
            lensName: "Test", green: green, red: green.map { $0 * 1.003 }, blue: green.map { $0 * 0.997 },
            vignetting: [Double](repeating: 1, count: 13), width: width, height: height,
        ))
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
        let light = (0 ..< 11).map { 1 - 0.05 * Double($0) }
        let correction = try #require(CameraLensCorrection(
            lensName: "Test", green: [Double](repeating: 1, count: 11), red: [Double](repeating: 1, count: 11),
            blue: [Double](repeating: 1, count: 11), vignetting: light, width: width, height: height,
        ))
        let corrected = LensWarp.apply(correction, to: positions(blue: 0.4), fullSize: size)
        #expect(abs(pixel(of: corrected, at: SIMD2(150, 100)).z - 0.4) < 0.001)
        for point in [SIMD2(0, 0), SIMD2(299, 120), SIMD2(40, 180)] {
            let source = correction.sourcePoint(ofCorrected: SIMD2(Double(point.x), Double(point.y)), channel: 2)
            let expected = 0.4 * correction.vignettingGain(at: source)
            let blue = Double(pixel(of: corrected, at: point).z)
            #expect(abs(blue - expected) < 0.002, "at \(point): \(blue), expected \(expected)")
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
