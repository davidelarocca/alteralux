import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxKit

/// The small lensfun-format database the lens tests read.
let lensFixtureDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxKitTests
    .deletingLastPathComponent() // Tests
    .appendingPathComponent("Fixtures/lensfun")

/// Reading a lensfun database and finding the lens of a photo in it.
struct LensDatabaseTests {
    private let database: LensDatabase

    init() throws {
        database = try LensDatabase(directory: lensFixtureDirectory)
    }

    private func info(
        maker: String = "SONY",
        camera: String = "ILCE-7M3",
        lens: String,
        focal: Double = 35,
        aperture: Double = 4,
    ) -> PhotoLensInfo {
        PhotoLensInfo(cameraMaker: maker, cameraModel: camera, lensModel: lens, focalLength: focal, aperture: aperture)
    }

    // MARK: Parsing

    @Test func everyFileOfTheFolderIsRead() {
        #expect(database.cameraCount == 5)
        #expect(database.lensCount == 9)
    }

    @Test func aBrokenFileIsReported() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lens-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("broken.xml")
        try Data("<lensdatabase><lens>".utf8).write(to: file)
        do {
            _ = try LensDatabase(directory: folder)
            Issue.record("A broken file was read")
        } catch let LensDatabaseError.unreadable(url) {
            #expect(url.lastPathComponent == file.lastPathComponent)
        }
    }

    @Test func aLensKeepsItsCalibrations() throws {
        let profile = try #require(database.lens(for: info(lens: "FE 24-70mm f/2.8 GM")))
        #expect(profile.lensName == "Sony FE 24-70mm f/2.8 GM")
        #expect(profile.lens.calibrations.distortion.count == 4)
        #expect(profile.lens.calibrations.tca.count == 2)
        #expect(profile.lens.calibrations.vignetting.count == 6)
        #expect(profile.lens.mounts == ["Sony E"])
        #expect(profile.lens.minFocal == 24)
        #expect(profile.lens.maxFocal == 70)
        // A distortion with no real focal length gets the one its model implies.
        let first = try #require(profile.lens.calibrations.distortion.first)
        #expect(abs(first.realFocal - 24 * (1 - 0.02824 + 0.07818 - 0.03129)) < 1e-9)
    }

    @Test func aLensKeepsItsAspectRatioAndCenter() throws {
        let profile = try #require(database.lens(for: info(maker: "Canon", camera: "Canon EOS 5D Mark IV", lens: "EF 35mm f/2 IS", focal: 35)))
        #expect(profile.lens.aspectRatio == 1.5)
        #expect(profile.lens.center == SIMD2(0.01, -0.02))
    }

    // MARK: Cameras

    @Test func aCameraIsFoundIgnoringCase() {
        let profile = database.lens(for: info(maker: "sony", camera: "ilce-7m3", lens: "FE 24-70mm f/2.8 GM"))
        #expect(profile?.lensName == "Sony FE 24-70mm f/2.8 GM")
    }

    @Test func aCameraIsFoundByATranslationOfItsName() {
        let profile = database.lens(for: info(camera: "Alpha 7 III", lens: "FE 24-70mm f/2.8 GM"))
        #expect(profile?.lensName == "Sony FE 24-70mm f/2.8 GM")
    }

    @Test func aMakerSpelledLongerOrShorterIsTheSameMaker() {
        let profile = database.lens(for: info(maker: "NIKON CORPORATION", camera: "NIKON D850", lens: "AF-S Nikkor 24-70mm f/2.8G ED", focal: 35))
        #expect(profile?.lensName == "Nikon Nikkor AF-S 24-70mm f/2.8G ED")
        let shorter = database.lens(for: info(maker: "Nikon", camera: "NIKON D850", lens: "AF-S Nikkor 24-70mm f/2.8G ED", focal: 35))
        #expect(shorter?.lensName == "Nikon Nikkor AF-S 24-70mm f/2.8G ED")
    }

    @Test func aMakerThatIsNotTheCamerasDoesNotMatchItsModel() {
        #expect(database.lens(for: info(maker: "Canon", camera: "ILCE-7M3", lens: "FE 24-70mm f/2.8 GM")) == nil)
    }

    @Test func anUnknownCameraGivesNothing() {
        #expect(database.lens(for: info(camera: "ILCE-9999", lens: "FE 24-70mm f/2.8 GM")) == nil)
        #expect(database.lens(for: info(camera: "", lens: "FE 24-70mm f/2.8 GM")) == nil)
    }

    // MARK: Lenses

    @Test func aLensIsFoundByItsExactName() {
        #expect(database.lens(for: info(lens: "FE 24-70mm f/2.8 GM"))?.lensName == "Sony FE 24-70mm f/2.8 GM")
    }

    @Test func aLensIsFoundUnderOtherSpellings() {
        let names = ["FE 24-70mm F2.8 GM", "Sony FE 24-70mm F2.8 GM", "fe 24-70mm f/2.8 gm", "FE 24.0-70.0 mm F2.8 GM"]
        for name in names {
            #expect(database.lens(for: info(lens: name))?.lensName == "Sony FE 24-70mm f/2.8 GM", "\(name)")
        }
    }

    @Test func theNumbersOfTheNameDecide() {
        #expect(database.lens(for: info(lens: "FE 24-70mm F2.8 GM II"))?.lensName == "Sony FE 24-70mm f/2.8 GM II")
        #expect(database.lens(for: info(lens: "FE 24-70mm F4 ZA OSS"))?.lensName == "Sony FE 24-70mm f/4 ZA OSS")
        #expect(database.lens(for: info(lens: "FE 24-105mm F4 G OSS")) == nil)
    }

    @Test func aLensOfAnotherMountIsNotTaken() {
        // The Canon lens exists in the database, but not for a Sony E camera.
        #expect(database.lens(for: info(lens: "Canon EF 50mm f/1.8 II", focal: 50)) == nil)
        let canon = database.lens(for: info(maker: "Canon", camera: "Canon EOS 5D Mark IV", lens: "EF 50mm f/1.8 II", focal: 50))
        #expect(canon?.lensName == "Canon Canon EF 50mm f/1.8 II")
    }

    @Test func aLensOfACompatibleMountIsTaken() {
        let profile = database.lens(for: info(lens: "Helios 44-2 58mm f/2", focal: 58))
        #expect(profile?.lensName == "Helios Helios 44-2 58mm f/2")
    }

    @Test func aLensCalibratedOnASmallerSensorIsNotTakenForALargerOne() {
        // The 18-55 is calibrated at a crop factor of 1.534: not for a full-frame camera.
        #expect(database.lens(for: info(lens: "E 18-55mm F3.5-5.6 OSS", focal: 24)) == nil)
        let small = database.lens(for: info(camera: "NEX-5N", lens: "E 18-55mm F3.5-5.6 OSS", focal: 24))
        #expect(small?.lensName == "Sony E 18-55mm f/3.5-5.6 OSS")
    }

    @Test func aLensWithAnotherFocalRangeIsNotTaken() {
        #expect(database.lens(for: info(lens: "FE 24-70mm f/2.8 GM", focal: 200)) == nil)
    }

    @Test func anUnknownLensGivesNothing() {
        #expect(database.lens(for: info(lens: "Something 85mm f/1.4")) == nil)
    }

    @Test func aFixedLensIsFoundWithoutAName() {
        let profile = database.lens(for: info(camera: "DSC-RX100", lens: "", focal: 20))
        // Under the camera's name: the database's own ("DSC-RX100 & compatibles (Standard)")
        // names the record, not the lens.
        #expect(profile?.lensName == "DSC-RX100")
        // An interchangeable-lens mount has too many lenses to tell which one.
        #expect(database.lens(for: info(lens: "")) == nil)
    }

    /// lensfun keeps the Ricoh GR III's own lens (18.3 mm) and the lens with its wide converter
    /// (13.8 mm) in one record, named after both: a photo without the converter gets the record,
    /// corrected at its own focal length, and is not said to have the converter.
    @Test func theGRIIIIsCorrectedAsItsOwnLensAndNamedAfterTheCamera() throws {
        let lensfun = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AlteraluxKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AlteraluxKit
            .deletingLastPathComponent() // apple
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("third_party/lensfun/db")
        let whole = try LensDatabase(directory: lensfun)
        func photo(focal: Double) -> PhotoLensInfo {
            info(maker: "RICOH IMAGING COMPANY, LTD.", camera: "RICOH GR III", lens: "", focal: focal, aperture: 5)
        }
        let profile = try #require(whole.lens(for: photo(focal: 18.3)))
        #expect(profile.lensName == "Ricoh GR III")
        let own = try #require(profile.correction(for: photo(focal: 18.3), imageWidth: 6000, imageHeight: 4000))
        let converter = try #require(profile.correction(for: photo(focal: 13.8), imageWidth: 6000, imageHeight: 4000))
        #expect(own != converter)
    }

    // MARK: Matching words

    @Test func namesAreCutIntoSortedWords() {
        let words = LensFuzzyMatch.words(of: "FE 24-70mm f/2.8 GM").map { String(bytes: $0, encoding: .utf8) }
        // "-", "/" and the lone "f" are dropped, case is folded and the words are sorted.
        #expect(words == ["2.8", "24", "70", "fe", "gm", "mm"])
        #expect(LensFuzzyMatch.words(of: "50.0mm") == LensFuzzyMatch.words(of: "50mm"))
    }

    @Test func aPatternMustHaveItsWordsInTheNameAndScoresByTheirShare() {
        let name = LensFuzzyMatch.words(of: "FE 24-70mm f/2.8 GM")
        #expect(LensFuzzyMatch.score(patternWords: name, nameWords: name) == 100)
        #expect(LensFuzzyMatch.score(patternWords: LensFuzzyMatch.words(of: "24-70mm"), nameWords: name) == 3 * 200 / 9)
        #expect(LensFuzzyMatch.score(patternWords: LensFuzzyMatch.words(of: "24-105mm"), nameWords: name) == 0)
        #expect(LensFuzzyMatch.score(patternWords: [], nameWords: name) == 0)
    }

    // MARK: The photo's metadata

    @Test func aPhotoTellsItsLens() throws {
        let url = try writePhoto(properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SONY", kCGImagePropertyTIFFModel: "ILCE-7M3"],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "FE 24-70mm F2.8 GM",
                kCGImagePropertyExifFocalLength: 35.0,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifSubjectDistance: 1.5,
            ],
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try #require(PhotoLensInfo.read(from: url))
        #expect(read == PhotoLensInfo(
            cameraMaker: "SONY",
            cameraModel: "ILCE-7M3",
            lensModel: "FE 24-70mm F2.8 GM",
            focalLength: 35,
            aperture: 2.8,
            focusDistance: 1.5,
        ))
    }

    @Test func aPhotoWithoutAFocalLengthOrACameraTellsNothing() throws {
        let noFocal = try writePhoto(properties: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "ILCE-7M3"]])
        let noCamera = try writePhoto(properties: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifFocalLength: 35.0]])
        defer {
            try? FileManager.default.removeItem(at: noFocal)
            try? FileManager.default.removeItem(at: noCamera)
        }
        #expect(PhotoLensInfo.read(from: noFocal) == nil)
        #expect(PhotoLensInfo.read(from: noCamera) == nil)
        #expect(PhotoLensInfo.read(from: URL(fileURLWithPath: "/nonexistent/photo.jpg")) == nil)
    }

    private func writePhoto(properties: [CFString: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lens-\(UUID().uuidString).jpg")
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}
