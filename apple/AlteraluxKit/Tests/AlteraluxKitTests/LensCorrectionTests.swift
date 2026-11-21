import Foundation
import Testing
@testable import AlteraluxKit

/// The corrections of a lens profile for a photo: interpolation of the calibrations, the units
/// and terms of each model, the zoom that fills the frame, and the reference mappings a kernel
/// has to match. The expected numbers are worked out here from lensfun's formulas, not read back
/// from the code under test.
/// A distortion calibration written out in the test.
private struct PtlensEntry {
    var focal: Double
    var terms: SIMD3<Double>

    var realFocal: Double {
        focal * (1 - terms.x - terms.y - terms.z)
    }
}

/// A vignetting calibration written out in the test.
private struct VignettingEntry {
    var focal: Double
    var aperture: Double
    var distance: Double
    var terms: SIMD3<Double>
}

struct LensCorrectionTests {
    private let database: LensDatabase
    private let width = 6000
    private let height = 4000
    /// The diagonal of a full-frame sensor, in millimeters.
    private let diagonal = hypot(36.0, 24.0)

    init() throws {
        database = try LensDatabase(directory: lensFixtureDirectory)
    }

    private func photo(
        _ lens: String,
        maker: String = "SONY",
        camera: String = "ILCE-7M3",
        focal: Double,
        aperture: Double = 0,
        distance: Double? = nil,
    ) -> PhotoLensInfo {
        PhotoLensInfo(
            cameraMaker: maker, cameraModel: camera, lensModel: lens, focalLength: focal, aperture: aperture, focusDistance: distance,
        )
    }

    private func correction(_ info: PhotoLensInfo, width: Int? = nil, height: Int? = nil) throws -> LensCorrection {
        let profile = try #require(database.lens(for: info))
        return try #require(profile.correction(for: info, imageWidth: width ?? self.width, imageHeight: height ?? self.height))
    }

    private func close(_ first: Double, _ second: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(first - second) <= tolerance * max(1, abs(second))
    }

    private func close(_ first: SIMD3<Double>, _ second: SIMD3<Double>, _ tolerance: Double = 1e-9) -> Bool {
        close(first.x, second.x, tolerance) && close(first.y, second.y, tolerance) && close(first.z, second.z, tolerance)
    }

    /// Lensfun's cubic Hermite spline between `second` and `third`.
    private func hermite(_ first: Double?, _ second: Double, _ third: Double, _ fourth: Double?, _ fraction: Double) -> Double {
        let slopeIn = first.map { (third - $0) / 2 } ?? third - second
        let slopeOut = fourth.map { ($0 - second) / 2 } ?? third - second
        let square = fraction * fraction
        let cube = square * fraction
        return (2 * cube - 3 * square + 1) * second + (cube - 2 * square + fraction) * slopeIn
            + (-2 * cube + 3 * square) * third + (cube - square) * slopeOut
    }

    // MARK: Distortion models

    @Test func aPtlensCalibrationIsRescaledToTheLensUnits() throws {
        let result = try correction(photo("FE 24-70mm f/2.8 GM", focal: 24))
        #expect(result.lensName == "Sony FE 24-70mm f/2.8 GM")
        #expect(result.distortionModel == .ptlens)
        // The calibration's real focal length is focal * d with d = 1 - a - b - c, and the unit of
        // its radius is half the height of its (3:2) sensor: 12 mm.
        let terms = SIMD3(0.02824, -0.07818, 0.03129)
        let shrink = 1 - terms.x - terms.y - terms.z
        let scaling = 24 * shrink / 12
        let expected = SIMD3(
            terms.x * pow(scaling, 3) / pow(shrink, 4), terms.y * pow(scaling, 2) / pow(shrink, 3), terms.z * scaling / pow(shrink, 2),
        )
        #expect(close(result.distortionTerms, expected))
        // One lens unit is the real focal length, which the photo's diagonal covers
        // diagonal / (crop * real focal) times.
        #expect(close(result.distortionUnit, hypot(6000, 4000) * 24 * shrink / diagonal))
        #expect(close(result.vignettingUnit, result.distortionUnit))
    }

    @Test func aPoly3CalibrationIsRescaledToTheLensUnits() throws {
        let info = photo("EF 50mm f/1.8 II", maker: "Canon", camera: "Canon EOS 5D Mark IV", focal: 50)
        let result = try correction(info)
        #expect(result.distortionModel == .poly3)
        let cubic = -0.0210
        let scaling = 50 * (1 - cubic) / 12
        #expect(close(result.distortionTerms, SIMD3(cubic * scaling * scaling / pow(1 - cubic, 3), 0, 0)))
    }

    @Test func aPoly5CalibrationUsesTheNominalFocalLength() throws {
        let info = photo("EF 35mm f/2 IS", maker: "Canon", camera: "Canon EOS 5D Mark IV", focal: 35)
        let result = try correction(info)
        #expect(result.distortionModel == .poly5)
        let scaling = 35.0 / 12
        #expect(close(result.distortionTerms, SIMD3(0.0100 * pow(scaling, 2), -0.0050 * pow(scaling, 4), 0)))
        // The lens's optical center is a little off the middle: by 1% and -2% of half the short side.
        let size = 3999.0
        #expect(close(result.center.x, 5999 / 2 + size / 2 * 0.01))
        #expect(close(result.center.y, 3999 / 2 - size / 2 * 0.02))
    }

    @Test func eachDistortionModelMapsRadiiAsItsFormulaSays() {
        let radii = [0.0, 0.25, 0.5, 0.9]
        let poly3 = SIMD3(-0.05, 0, 0)
        let poly5 = SIMD3(0.03, -0.02, 0)
        let ptlens = SIMD3(0.01, -0.03, 0.02)
        for radius in radii {
            let point = SIMD2(radius, 0)
            #expect(close(LensCorrection.distort(point, model: .none, terms: poly3).x, radius))
            #expect(close(LensCorrection.distort(point, model: .poly3, terms: poly3).x, radius * (1 + poly3.x * radius * radius)))
            #expect(close(
                LensCorrection.distort(point, model: .poly5, terms: poly5).x,
                radius * (1 + poly5.x * pow(radius, 2) + poly5.y * pow(radius, 4)),
            ))
            #expect(close(
                LensCorrection.distort(point, model: .ptlens, terms: ptlens).x,
                radius * (ptlens.x * pow(radius, 3) + ptlens.y * pow(radius, 2) + ptlens.z * radius + 1),
            ))
        }
        // The direction of a point is kept.
        let moved = LensCorrection.distort(SIMD2(0.3, 0.4), model: .poly3, terms: poly3)
        #expect(close(moved.y / moved.x, 0.4 / 0.3))
    }

    @Test func theReferenceMappingAppliesScaleThenDistortion() throws {
        let info = photo("EF 50mm f/1.8 II", maker: "Canon", camera: "Canon EOS 5D Mark IV", focal: 50)
        let result = try correction(info)
        let cubic = result.distortionTerms.x
        for offset in [0.0, 300, 1200, 2500] {
            let point = result.center + SIMD2(offset, offset / 2)
            let unitPoint = SIMD2(offset, offset / 2) / (result.distortionUnit * result.scale)
            let radiusSquared = unitPoint.x * unitPoint.x + unitPoint.y * unitPoint.y
            let expected = result.center + unitPoint * (1 + cubic * radiusSquared) * result.distortionUnit
            for channel in 0 ..< 3 {
                let source = result.sourcePoint(ofCorrected: point, channel: channel)
                #expect(close(source.x, expected.x, 1e-9) && close(source.y, expected.y, 1e-9))
            }
        }
        // Nothing moves at the center.
        #expect(result.sourcePoint(ofCorrected: result.center, channel: 1) == result.center)
    }

    // MARK: Interpolation

    @Test func aFocalLengthBetweenTwoCalibrationsGetsASplineThroughThem() throws {
        let calibrations = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 30))).lens.calibrations
        let result = try #require(calibrations.distortion(at: 30))
        // Calibrated at 24, 35, 50 and 70: at 30 the spline runs from 35 down to 24, with the 50
        // before 35 and nothing after 24. The terms follow a 1/f law, so they are multiplied by
        // the focal length for the interpolation and divided by the target's after.
        let entries = [
            PtlensEntry(focal: 24, terms: SIMD3(0.02824, -0.07818, 0.03129)),
            PtlensEntry(focal: 35, terms: SIMD3(0.01259, -0.01412, -0.00168)),
            PtlensEntry(focal: 50, terms: SIMD3(0.00279, 0.01446, -0.01735)),
        ]
        let fraction = (30.0 - 35) / (24 - 35)
        var expected = SIMD3<Double>.zero
        for index in 0 ..< 3 {
            expected[index] = hermite(
                entries[2].focal * entries[2].terms[index],
                entries[1].focal * entries[1].terms[index],
                entries[0].focal * entries[0].terms[index],
                nil,
                fraction,
            ) / 30
        }
        #expect(close(result.terms, expected))
        #expect(result.model == .ptlens)
        // Real focal lengths follow the same spline.
        #expect(close(result.realFocal, hermite(entries[2].realFocal, entries[1].realFocal, entries[0].realFocal, nil, fraction)))
    }

    @Test func aCalibratedFocalLengthIsUsedAsItIs() throws {
        let calibrations = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 35))).lens.calibrations
        let result = try #require(calibrations.distortion(at: 35))
        #expect(result.terms == SIMD3(0.01259, -0.01412, -0.00168))
    }

    @Test func beyondTheCalibratedRangeTheNearestCalibrationIsUsed() throws {
        let calibrations = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 30))).lens.calibrations
        #expect(try #require(calibrations.distortion(at: 20)).terms == SIMD3(0.02824, -0.07818, 0.03129))
        #expect(try #require(calibrations.distortion(at: 100)).terms == SIMD3(0.00719, -0.01275, 0.0241))
    }

    @Test func fringingBetweenTwoFocalLengthsInterpolatesLinearlyForTheConstantTerm() throws {
        // Two calibrations, 24 and 70: a straight line between them for the first terms; the
        // others, scaled by the focal length, are all zero at 24.
        let calibrations = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 47))).lens.calibrations
        let result = try #require(calibrations.tca(at: 47))
        let fraction = (47.0 - 70) / (24 - 70)
        #expect(close(result.terms[0], hermite(nil, 0.9998908, 1.0001797, nil, fraction)))
        #expect(close(result.terms[1], hermite(nil, 0.9998780, 1.0001569, nil, fraction)))
        #expect(close(result.terms[2], hermite(nil, 0.0001 * 70, 0, nil, fraction) / 47))
        #expect(close(result.terms[5], hermite(nil, 0.0002 * 70, 0, nil, fraction) / 47))
    }

    @Test func vignettingAtACalibratedSettingIsUsedAsItIs() throws {
        let result = try correction(photo("FE 24-70mm f/2.8 GM", focal: 24, aperture: 2.8, distance: 1000))
        // Half the diagonal of the calibration's sensor is the unit of its radius.
        let real = 24 * (1 - 0.02824 + 0.07818 - 0.03129)
        let scaling = real / (diagonal / 2)
        #expect(close(result.vignettingTerms, SIMD3(-0.5106 * pow(scaling, 2), -0.3627 * pow(scaling, 4), 0.1448 * pow(scaling, 6))))
        #expect(result.correctsVignetting)
        let other = try correction(photo("FE 24-70mm f/2.8 GM", focal: 24, aperture: 4, distance: 1000))
        #expect(close(other.vignettingTerms, SIMD3(-0.4 * pow(scaling, 2), -0.2 * pow(scaling, 4), 0.05 * pow(scaling, 6))))
    }

    @Test func vignettingBetweenAperturesAndDistancesIsAnInverseDistanceWeightedMean() throws {
        let profile = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 24)))
        // Focal 24 (the lens ranges over 24...70), f/3.3, 100 m: every calibration weighs in.
        let entries = [
            VignettingEntry(focal: 24, aperture: 2.8, distance: 1000, terms: SIMD3(-0.5106, -0.3627, 0.1448)),
            VignettingEntry(focal: 24, aperture: 2.8, distance: 10, terms: SIMD3(-0.5106, -0.3627, 0.1448)),
            VignettingEntry(focal: 24, aperture: 4, distance: 1000, terms: SIMD3(-0.4, -0.2, 0.05)),
            VignettingEntry(focal: 24, aperture: 4, distance: 10, terms: SIMD3(-0.4, -0.2, 0.05)),
            VignettingEntry(focal: 70, aperture: 2.8, distance: 1000, terms: SIMD3(-0.6241, 0.8333, -0.7866)),
            VignettingEntry(focal: 70, aperture: 2.8, distance: 10, terms: SIMD3(-0.6241, 0.8333, -0.7866)),
        ]
        let focal = 24.0
        let aperture = 3.3
        let distance = 100.0
        var total = SIMD3<Double>.zero
        var weights = 0.0
        for entry in entries {
            let gap = hypot(
                hypot((entry.focal - focal) / 46, 4 / entry.aperture - 4 / aperture),
                0.1 / entry.distance - 0.1 / distance,
            )
            let weight = 1 / pow(gap, 3.5)
            total += weight * entry.terms
            weights += weight
        }
        let result = try #require(profile.lens.calibrations.vignetting(focal: focal, aperture: aperture, distance: distance, focalRange: 24 ... 70))
        #expect(close(result, total / weights))
        // Between the two apertures the terms lie between theirs.
        #expect(result.x < -0.4 && result.x > -0.5106)
    }

    @Test func vignettingBetweenFocalLengthsMixesTheNearCalibrations() throws {
        let profile = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 47)))
        let near = try #require(profile.lens.calibrations.vignetting(focal: 30, aperture: 2.8, distance: 1000, focalRange: 24 ... 70))
        let far = try #require(profile.lens.calibrations.vignetting(focal: 60, aperture: 2.8, distance: 1000, focalRange: 24 ... 70))
        // 30 is nearer the 24 calibration and 60 the 70 one.
        #expect(abs(near.x - -0.5106) < abs(near.x - -0.6241))
        #expect(abs(far.x - -0.6241) < abs(far.x - -0.5106))
    }

    @Test func noVignettingIsGivenWhenNoCalibrationIsNear() throws {
        // At 70 mm and f/22 the nearest calibration (70 mm, f/2.8) is more than 1 away in the
        // weighting space, where the aperture counts by its reciprocal.
        let result = try correction(photo("FE 24-70mm f/2.8 GM", focal: 70, aperture: 22, distance: 1000))
        #expect(!result.correctsVignetting)
        #expect(result.vignettingGain(at: SIMD2(0, 0)) == 1)
        // Neither when the photo does not say its aperture.
        #expect(try !correction(photo("FE 24-70mm f/2.8 GM", focal: 24)).correctsVignetting)
    }

    @Test func theVignettingGainFollowsItsFormulaFromTheCenter() throws {
        let result = try correction(photo("FE 24-70mm f/2.8 GM", focal: 24, aperture: 2.8, distance: 1000))
        #expect(result.vignettingGain(at: result.center) == 1)
        let corner = SIMD2(0.0, 0.0)
        let radiusSquared = pow(hypot(result.center.x, result.center.y) / result.vignettingUnit, 2)
        let terms = result.vignettingTerms
        let expected = 1 / (1 + terms.x * radiusSquared + terms.y * pow(radiusSquared, 2) + terms.z * pow(radiusSquared, 3))
        #expect(close(result.vignettingGain(at: corner), expected))
        // A vignetted corner is darker than the middle, so it is brightened.
        #expect(result.vignettingGain(at: corner) > 1)
    }

    // MARK: Fringing

    @Test func aLinearFringingScalesTheRedAndTheBlueFromTheCenter() throws {
        let info = photo("EF 35mm f/2 IS", maker: "Canon", camera: "Canon EOS 5D Mark IV", focal: 35)
        let result = try correction(info)
        #expect(result.tcaModel == .linear)
        #expect(result.tcaRed == SIMD3(1.0002, 0, 0))
        #expect(result.tcaBlue == SIMD3(0.9997, 0, 0))
        let point = result.center + SIMD2(1500, -900)
        let green = result.sourcePoint(ofCorrected: point, channel: 1) - result.center
        let red = result.sourcePoint(ofCorrected: point, channel: 0) - result.center
        let blue = result.sourcePoint(ofCorrected: point, channel: 2) - result.center
        #expect(close(red.x, green.x * 1.0002, 1e-12) && close(red.y, green.y * 1.0002, 1e-12))
        #expect(close(blue.x, green.x * 0.9997, 1e-12) && close(blue.y, green.y * 0.9997, 1e-12))
    }

    @Test func aPoly3FringingIsRescaledToTheLensUnits() throws {
        let result = try correction(photo("FE 24-70mm f/2.8 GM", focal: 70))
        #expect(result.tcaModel == .poly3)
        let real = 70 * (1 - 0.00719 + 0.01275 - 0.0241)
        let scaling = real / 12
        #expect(close(result.tcaRed, SIMD3(0.9998908, 0.0001 * scaling, -0.0002 * scaling * scaling)))
        #expect(close(result.tcaBlue, SIMD3(0.9998780, -0.0001 * scaling, 0.0002 * scaling * scaling)))
        // Worked through the polynomial: the red channel of a point is scaled by v + c r + b r^2.
        let point = result.center + SIMD2(2000, 1000)
        let green = result.sourcePoint(ofCorrected: point, channel: 1) - result.center
        let radius = hypot(green.x, green.y) / result.distortionUnit
        let factor = result.tcaRed.x + result.tcaRed.y * radius + result.tcaRed.z * radius * radius
        let red = result.sourcePoint(ofCorrected: point, channel: 0) - result.center
        #expect(close(red.x, green.x * factor, 1e-12))
    }

    // MARK: Filling the frame

    @Test func theCornersOfTheCorrectedPictureLandInsideTheShotOne() throws {
        let infos = [
            photo("FE 24-70mm f/2.8 GM", focal: 24),
            photo("FE 24-70mm f/2.8 GM", focal: 50),
            photo("EF 50mm f/1.8 II", maker: "Canon", camera: "Canon EOS 5D Mark IV", focal: 50),
            photo("EF 35mm f/2 IS", maker: "Canon", camera: "Canon EOS 5D Mark IV", focal: 35),
            photo("E 18-55mm F3.5-5.6 OSS", camera: "NEX-5N", focal: 18),
        ]
        for info in infos {
            let result = try correction(info)
            let (maxX, maxY) = (Double(width - 1), Double(height - 1))
            let points = [
                SIMD2(0, 0), SIMD2(maxX, 0), SIMD2(0, maxY), SIMD2(maxX, maxY),
                SIMD2(maxX / 2, 0), SIMD2(maxX / 2, maxY), SIMD2(0, maxY / 2), SIMD2(maxX, maxY / 2),
            ]
            var touches = false
            for channel in 0 ..< 3 {
                for point in points {
                    let source = result.sourcePoint(ofCorrected: point, channel: channel)
                    let slack = 1e-6 + 0.004 * maxX // the permille margin, and the fringing's, can reach the rim
                    #expect(source.x >= -slack && source.x <= maxX + slack, "\(info.lensModel) \(point) \(source)")
                    #expect(source.y >= -slack && source.y <= maxY + slack, "\(info.lensModel) \(point) \(source)")
                    if channel == 1 {
                        // Nothing is wasted either: some point of the frame is at the very rim.
                        let nearEdge = min(source.x, maxX - source.x, source.y, maxY - source.y)
                        touches = touches || nearEdge < 0.01 * maxX
                    }
                }
            }
            #expect(touches, "\(info.lensModel) leaves a margin")
        }
    }

    @Test func aLensWithoutDistortionNeedsNoZoomButAFringingMargin() {
        let scale = LensCorrection.autoScale(model: .none, terms: .zero, span: SIMD2(5999, 3999), unitsPerPixel: 0.001, hasFringing: false)
        #expect(scale == 1)
        #expect(LensCorrection.autoScale(model: .none, terms: .zero, span: SIMD2(5999, 3999), unitsPerPixel: 0.001, hasFringing: true) == 1.001)
    }

    @Test func aBarrelLensIsZoomedIn() {
        // Rd = Ru * (1 + 0.1 Ru^2): a point of the corrected picture comes from farther out, so the
        // picture is magnified until its edge is inside the shot one.
        let scale = LensCorrection.autoScale(model: .poly3, terms: SIMD3(0.1, 0, 0), span: SIMD2(3000, 2000), unitsPerPixel: 1 / 3000, hasFringing: false)
        #expect(scale > 1)
        let halfX = 1500.0 / 3000
        let halfY = 1000.0 / 3000
        let corner = LensCorrection.distort(SIMD2(halfX, halfY) / scale, model: .poly3, terms: SIMD3(0.1, 0, 0))
        #expect(corner.x <= halfX * 1.0001 && corner.y <= halfY * 1.0001)
    }

    // MARK: Sensor size

    @Test func theSamePhotoOnASmallerSensorSpansFewerLensUnits() throws {
        // The GM is calibrated on a crop factor of 1.0. On an APS-C camera (1.534) the same
        // pixels cover a smaller field: the terms are the lens's, the unit grows with the crop.
        let full = try correction(photo("FE 24-70mm f/2.8 GM", focal: 35))
        let profile = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", camera: "NEX-5N", focal: 35)))
        let small = try #require(profile.correction(for: photo("FE 24-70mm f/2.8 GM", camera: "NEX-5N", focal: 35), imageWidth: 6000, imageHeight: 4000))
        #expect(close(small.distortionTerms, full.distortionTerms))
        #expect(close(small.distortionUnit / full.distortionUnit, 1.534))
        #expect(close(small.vignettingUnit / full.vignettingUnit, 1.534))
    }

    @Test func thePhotosAspectRatioSetsTheUnitNotTheLensesCalibration() throws {
        // A 4:3 photo of 4000 x 3000 pixels has a shorter diagonal than 6000 x 4000.
        let wide = try correction(photo("FE 24-70mm f/2.8 GM", focal: 35))
        let narrow = try correction(photo("FE 24-70mm f/2.8 GM", focal: 35), width: 4000, height: 3000)
        #expect(close(narrow.distortionUnit / wide.distortionUnit, hypot(4000, 3000) / hypot(6000, 4000)))
        #expect(close(narrow.distortionTerms, wide.distortionTerms))
        #expect(narrow.center == SIMD2<Double>(1999.5, 1499.5), "\(narrow.center)")
    }

    @Test func aCalibrationRatioOfTheLensAndTheCameraRescalesTheTermsOfTheLensSensor() throws {
        // The 18-55 is calibrated on 1.534 with a 3:2 sensor; its poly3 terms are rescaled with that
        // sensor's half height: 43.27 / 1.534 / hypot(1.5, 1) / 2 = 7.8 mm.
        let info = photo("E 18-55mm F3.5-5.6 OSS", camera: "NEX-5N", focal: 18)
        let result = try correction(info)
        let cubic = -0.0295
        let scaling = 18 * (1 - cubic) / (diagonal / 1.534 / hypot(1.5, 1) / 2)
        #expect(close(result.distortionTerms, SIMD3(cubic * scaling * scaling / pow(1 - cubic, 3), 0, 0)))
    }

    // MARK: Nothing to correct

    @Test func aPhotoWithoutAFocalLengthGetsNothing() throws {
        let profile = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 35)))
        let info = photo("FE 24-70mm f/2.8 GM", focal: 0)
        #expect(profile.correction(for: info, imageWidth: 6000, imageHeight: 4000) == nil)
        #expect(profile.correction(for: photo("FE 24-70mm f/2.8 GM", focal: 35), imageWidth: 0, imageHeight: 4000) == nil)
    }

    @Test func aLensWithOnlyVignettingStillCorrects() throws {
        let profile = try #require(database.lens(for: photo("FE 24-70mm f/2.8 GM", focal: 35)))
        var lens = profile.lens
        lens.calibrations.distortion = []
        lens.calibrations.tca = []
        let vignettingOnly = LensProfile(lens: lens, cameraCropFactor: 1)
        let info = photo("FE 24-70mm f/2.8 GM", focal: 24, aperture: 2.8, distance: 1000)
        let result = try #require(vignettingOnly.correction(for: info, imageWidth: 6000, imageHeight: 4000))
        #expect(!result.correctsDistortion && !result.correctsFringing && result.correctsVignetting)
        #expect(result.scale == 1)
        #expect(result.sourcePoint(ofCorrected: SIMD2(10, 20), channel: 0) == SIMD2(10, 20))
    }
}
