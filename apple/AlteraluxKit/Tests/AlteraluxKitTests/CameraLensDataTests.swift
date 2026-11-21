import Foundation
import Testing
@testable import AlteraluxKit

/// The readers of the lens corrections cameras record, on small files laid out as each maker lays
/// out its RAWs. The numbers of the real files they were checked on are in ADR 0015.
struct CameraLensDataTests {
    // MARK: Sony

    /// The numbers a Sony ZV-E10 recorded with a Viltrox 56mm F1.7 at f/1.7: eleven knots each.
    static let sonyDistortion = [11, 2, 3, 6, 13, 23, 37, 53, 71, 90, 111, 131, 0, 0, 0, 0, 0]
    static let sonyAberration = [22] + [Int](repeating: -256, count: 22) + [Int](repeating: 0, count: 10)
    static let sonyVignetting = [11, 0, 352, 1152, 2304, 3712, 5280, 6880, 8448, 9888, 11200, 12288, 0, 0, 0, 0, 0]

    static func arw(
        maker: String = "SONY", distortion: [Int] = sonyDistortion, aberration: [Int] = sonyAberration,
        vignetting: [Int] = sonyVignetting, littleEndian: Bool = true,
    ) -> Data {
        let raw = TIFFBuilder.Directory(entries: [
            (0x7032, .signedShorts(vignetting)), (0x7035, .signedShorts(aberration)), (0x7037, .signedShorts(distortion)),
        ])
        let preview = TIFFBuilder.Directory(entries: [(0x0100, .longs([160]))])
        let main = TIFFBuilder.Directory(entries: [(0x010F, .ascii(maker)), (0x014A, .directories([preview, raw]))])
        return Data(TIFFBuilder(littleEndian: littleEndian).build(main))
    }

    @Test func sonyCurvesAreReadWithTheirKnotsFromCenterToCorner() throws {
        let data = try #require(SonyLensData.read(Self.arw()))
        let geometry = try #require(data.geometry)
        #expect(data.maker == .sony)
        #expect(geometry.green.radii.count == 11)
        #expect(geometry.green.value(at: 0) == 1 + 2.0 / 16384)
        #expect(geometry.green.value(at: 1) == 1 + 131.0 / 16384)
        #expect(abs(geometry.green.value(at: 0.55) - (1 + 45.0 / 16384)) < 1e-12)
        #expect(abs(geometry.red.value(at: 0.3) - geometry.green.value(at: 0.3) * (1 - 256.0 / 2_097_152)) < 1e-15)
        let light = try #require(data.vignetting)
        let kept = pow(2, 0.5 - pow(2, 12288.0 / 8192 - 1))
        #expect(abs(light.value(at: 1) - kept * kept) < 1e-12)
        // About -1.8 EV at the corner.
        #expect(abs(log2(light.value(at: 1)) + 1.83) < 0.01)
    }

    @Test func sonyReadsTheSameInEitherByteOrderAndFromAnySubdirectory() {
        #expect(SonyLensData.read(Self.arw(littleEndian: false)) == SonyLensData.read(Self.arw()))
        #expect(SonyLensData.read(Self.arw()) != nil)
    }

    @Test func sonyVignettingMayHaveItsOwnNumberOfKnots() throws {
        let vignetting = [16] + (0 ..< 16).map { $0 * 400 }
        let data = try #require(SonyLensData.read(Self.arw(vignetting: vignetting)))
        #expect(data.vignetting?.radii.count == 16)
        #expect(data.geometry?.green.radii.count == 11)
    }

    @Test func sonyTagsThatDoNotFitAreLeftOut() throws {
        #expect(SonyLensData.read(Self.arw(maker: "FUJIFILM")) == nil)
        // Fringes that do not match the distortion's knots: the distortion alone.
        let noFringes = try #require(SonyLensData.read(Self.arw(aberration: [20] + [Int](repeating: 9, count: 20))))
        #expect(noFringes.geometry?.red == noFringes.geometry?.green)
        let tooMany = try #require(SonyLensData.read(Self.arw(distortion: [17] + [Int](repeating: 1, count: 17))))
        #expect(tooMany.geometry == nil && tooMany.vignetting != nil)
        #expect(SonyLensData.read(Data("not a tiff".utf8)) == nil)
        #expect(SonyLensData.read(Data(Self.arw().prefix(40))) == nil)
    }

    @Test func aCameraThatRecordedNothingCorrectsNothing() {
        let zeros = [11] + [Int](repeating: 0, count: 16)
        let noAberration = [22] + [Int](repeating: 0, count: 32)
        #expect(SonyLensData.read(Self.arw(distortion: zeros, aberration: noAberration, vignetting: zeros)) == nil)
    }

    // MARK: Fujifilm

    static let fujiDistortion = [416.5, 0.5, 0.75, 1.0, -1, -2, -4]
    static let fujiAberration = [416.5, 0.5, 0.75, 1.0, 0.001, 0.002, 0.003, -0.001, -0.002, -0.003]
    static let fujiVignetting = [416.5, 0.5, 0.75, 1.0, 95, 85, 70]

    /// A RAF: its header, and at the offset byte 100 gives, a TIFF whose 0xF000 directory holds
    /// the three tables.
    static func raf() -> Data {
        let fuji = TIFFBuilder.Directory(entries: [
            (0xF00B, .signedRationals(fujiDistortion)), (0xF00F, .signedRationals(fujiAberration)),
            (0xF010, .signedRationals(fujiVignetting)),
        ])
        let tiff = TIFFBuilder(littleEndian: false).build(TIFFBuilder.Directory(entries: [(0xF000, .directories([fuji]))]))
        var header = Array("FUJIFILMCCD-RAW 0201FF383501".utf8)
        header += [UInt8](repeating: 0, count: 160 - header.count)
        header.replaceSubrange(100 ..< 104, with: [0, 0, 0, 160])
        return Data(header + tiff)
    }

    @Test func fujifilmTablesMoveToTheCorrectedRadii() throws {
        let data = try #require(FujifilmLensData.read(Self.raf()))
        let geometry = try #require(data.geometry)
        #expect(data.maker == .fujifilm)
        #expect(abs(geometry.green.value(at: 0) - 1) < 1e-9)
        // A point shot at 1.0 is corrected to 1 / 0.96, and comes from 0.96 times further out.
        #expect(abs(geometry.green.value(at: 1 / 0.96) - 0.96) < 1e-3)
        #expect(abs(geometry.green.value(at: 0.5 / 0.99) - 0.99) < 1e-3)
        #expect(abs(geometry.red.value(at: 1 / 0.96) - 0.96 * 1.003) < 1e-3)
        #expect(abs(geometry.blue.value(at: 1 / 0.96) - 0.96 * 0.997) < 1e-3)
        let light = try #require(data.vignetting)
        #expect(light.value(at: 0) == 1)
        #expect(abs(light.value(at: 1) - 0.70) < 1e-9)
        #expect(abs(light.value(at: 0.75) - 0.85) < 1e-9)
    }

    @Test func fujifilmCropModesScaleTheRadii() throws {
        let data = try #require(FujifilmLensData.curves(
            distortion: Self.fujiDistortion, aberration: nil, vignetting: Self.fujiVignetting, cropFactor: 1.25,
        ))
        #expect(abs((data.vignetting?.value(at: 1.25) ?? 0) - 0.70) < 1e-9)
        #expect(data.geometry?.red == data.geometry?.green)
    }

    @Test func fujifilmFringesMayLackTheFirstRadius() throws {
        // The older tables: eleven radii from 0, fringes on the ten after it, and one more value.
        let radii = (0 ... 10).map { Double($0) / 10 }
        let distortion = [327.7] + radii + radii.map { -$0 }
        let aberration = [360.5] + Array(radii.dropFirst()) + [Double](repeating: 0.002, count: 10)
            + [Double](repeating: -0.002, count: 10)
        let data = try #require(FujifilmLensData.curves(distortion: distortion, aberration: aberration, vignetting: nil, cropFactor: 1))
        let geometry = try #require(data.geometry)
        #expect(abs(geometry.red.value(at: 0.5) / geometry.green.value(at: 0.5) - 1.002) < 1e-6)
        #expect(abs(geometry.blue.value(at: 0.5) / geometry.green.value(at: 0.5) - 0.998) < 1e-6)
    }

    // MARK: Nikon

    /// One correction set of Nikon's blob: a version, a flag, then at 0x10 the count and the
    /// rationals.
    static func nikonSet(_ terms: [Double], last: Double, littleEndian: Bool = true) -> [UInt8] {
        let builder = TIFFBuilder(littleEndian: littleEndian)
        let rationals = (terms + [last]).flatMap { builder.encode(Int(($0 * 1_000_000).rounded()), 4) + builder.encode(1_000_000, 4) }
        return builder.encode(terms.count, 4) + rationals
    }

    static func nef() -> Data {
        let header = Array("0100".utf8) + [1] + [UInt8](repeating: 0, count: 11)
        let trailer = [UInt8](repeating: 0, count: 28)
        let inner = TIFFBuilder(littleEndian: true).build(TIFFBuilder.Directory(entries: [
            (5, .bytes(header + nikonSet([0.01, -0.02, 0.03, 0], last: 0) + trailer)),
            (6, .bytes(header + nikonSet([0, 0, 0, 0, 0, 0, 0.5, 0], last: 1) + trailer)),
            (7, .bytes(header + nikonSet([0, 0, 0.0001], last: 0.00005) + nikonSet([0, 0, -0.0001], last: 0) + trailer)),
        ]))
        let blob = Array("Nikon\0".utf8) + [1, 1, 0, 0] + inner
        let raw = TIFFBuilder.Directory(entries: [(0xC7D5, .bytes(blob))])
        let main = TIFFBuilder.Directory(entries: [(0x010F, .ascii("NIKON CORPORATION")), (0x014A, .directories([raw]))])
        return Data(TIFFBuilder(littleEndian: false).build(main))
    }

    @Test func nikonPolynomialsAreReadHighestPowerFirst() throws {
        let data = try #require(NikonLensData.read(Self.nef()))
        let geometry = try #require(data.geometry)
        #expect(data.maker == .nikon)
        #expect(abs(geometry.green.value(at: 1) - 1.02) < 1e-6)
        #expect(abs(geometry.green.value(at: 0.5) - (1 + 0.01 / 16 - 0.02 / 8 + 0.03 / 4)) < 1e-5)
        #expect(abs(geometry.red.value(at: 1) - 1.02 * 1.00015) < 1e-6)
        #expect(abs(geometry.blue.value(at: 1) - 1.02 * 0.9999) < 1e-6)
        // The vignetting polynomial is the gain: 1 + 0.5 r^2.
        #expect(abs((data.vignetting?.value(at: 1) ?? 0) - 1 / 1.5) < 1e-6)
    }

    // MARK: Olympus

    static func orf(distortion: [Double] = [0.01, 0.002, -0.001, 0.99]) -> Data {
        let builder = TIFFBuilder(littleEndian: true)
        // The maker note: its header, then a directory at 12 pointing at ImageProcessing, all
        // offsets from the note's start.
        var note = Array("OLYMPUS\0II".utf8) + [3, 0]
        note += builder.encode(1, 2) + builder.encode(0x2040, 2) + builder.encode(13, 2) + builder.encode(1, 4)
        let pointer = note.count
        note += builder.encode(0, 4) + builder.encode(0, 4)
        let processing = TIFFBuilder.Directory(entries: [
            (0x150A, .floats(distortion)),
            (0x150C, .floats([0.0002, 0, 0, -0.0002, 0, 0])),
        ])
        let offset = builder.write(processing, into: &note)
        note.replaceSubrange(pointer ..< pointer + 4, with: builder.encode(offset, 4))
        let exif = TIFFBuilder.Directory(entries: [(0x927C, .bytes(note))])
        let orf = TIFFBuilder(littleEndian: true, magic: 0x4F52)
        return Data(orf.build(TIFFBuilder.Directory(entries: [(0x8769, .directories([exif]))])))
    }

    @Test func olympusDistortionAndFringesFollowTheirPolynomials() throws {
        let data = try #require(OlympusLensData.read(Self.orf()))
        let geometry = try #require(data.geometry)
        #expect(data.maker == .olympus && data.vignetting == nil)
        let square = 0.99 * 0.99
        let factor = 0.99 * (1 + square * (0.01 + square * (0.002 + square * -0.001)))
        #expect(abs(geometry.green.value(at: 1) - factor) < 1e-5)
        #expect(abs(geometry.green.value(at: 0) - 0.99) < 1e-6)
        // Red moves out by 0.0002 of the shot radius, blue in.
        #expect(abs(geometry.red.value(at: 1) - (factor + 0.0002 * factor)) < 1e-6)
        #expect(abs(geometry.blue.value(at: 1) - (factor - 0.0002 * factor)) < 1e-6)
    }

    @Test func olympusWithoutDistortionIsNotCorrected() {
        #expect(OlympusLensData.read(Self.orf(distortion: [0, 0, 0, 1])) == nil)
    }

    // MARK: Panasonic

    static func rw2(_ values: [Int]) -> Data {
        let bytes = values.flatMap { TIFFBuilder(littleEndian: true).encode($0, 2) }
        let builder = TIFFBuilder(littleEndian: true, magic: 0x55)
        return Data(builder.build(TIFFBuilder.Directory(entries: [(0x0119, .bytes(bytes))])))
    }

    static let panasonicOn = [0, 0, 0, 0, 0, 0, 0, 0xF001 - 0x10000, 3277, 0, 0, 0, 2500, 0, 0, 0]

    @Test func panasonicDistortionIsInvertedToTheCorrectedRadius() throws {
        let data = try #require(PanasonicLensData.read(Self.rw2(Self.panasonicOn)))
        let green = try #require(data.geometry?.green)
        let cubic = 3277.0 / 32768
        for corrected in [0.3, 0.8, 1.0] {
            let shot = corrected * green.value(at: corrected)
            // Ru = Rd + a Rd^3.
            #expect(abs(shot + cubic * shot * shot * shot - corrected) < 1e-4, "\(corrected)")
        }
    }

    @Test func panasonicCorrectionOffIsLeftAlone() {
        var off = Self.panasonicOn
        off[7] = 0
        #expect(PanasonicLensData.read(Self.rw2(off)) == nil)
    }

    // MARK: Files

    @Test func theReaderIsChosenByTheFilesKind() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files: [String: (data: Data, maker: CameraMaker?)] = [
            "photo.ARW": (Self.arw(), .sony), "photo.RAF": (Self.raf(), .fujifilm), "photo.NEF": (Self.nef(), .nikon),
            "photo.ORF": (Self.orf(), .olympus), "photo.RW2": (Self.rw2(Self.panasonicOn), .panasonic),
            "photo.tif": (Self.arw(), nil), "photo.dng": (Self.arw(), nil),
        ]
        for (name, (data, maker)) in files {
            let url = folder.appendingPathComponent(name)
            try data.write(to: url)
            #expect(CameraLensData.read(from: url)?.maker == maker, "\(name)")
        }
    }

    // MARK: Curves and the TIFF reader

    @Test func aCurveRunsStraightBetweenItsRadiiAndStaysFlatBeyond() throws {
        let curve = try #require(RadialCurve(radii: [0.2, 0.5, 1], values: [1, 2, 4]))
        #expect(curve.value(at: 0) == 1)
        #expect(abs(curve.value(at: 0.35) - 1.5) < 1e-12)
        #expect(abs(curve.value(at: 0.75) - 3) < 1e-12)
        #expect(curve.value(at: 3) == 4)
        #expect(RadialCurve(radii: [0.5, 0.2], values: [1, 2]) == nil)
        #expect(RadialCurve(radii: [0.5], values: [1, 2]) == nil)
        let sampled = RadialCurve(sampling: { 1 + $0 * $0 })
        #expect(abs(sampled.value(at: 0.77) - (1 + 0.77 * 0.77)) < 1e-4)
    }

    @Test func theTIFFReaderReadsEveryKindOfNumber() throws {
        let main = TIFFBuilder.Directory(entries: [
            (1, .signedShorts([-3, 7])), (2, .signedRationals([-0.25, 1.5])), (3, .floats([0.125])), (4, .ascii("ILCE")),
        ])
        for littleEndian in [true, false] {
            let data = Data(TIFFBuilder(littleEndian: littleEndian).build(main))
            let reader = try #require(TIFFReader(data: data))
            let directory = try #require(reader.directory(at: reader.firstDirectory))
            #expect(reader.integers(directory[1]) == [-3, 7])
            #expect(reader.numbers(directory[2]) == [-0.25, 1.5])
            #expect(reader.numbers(directory[3]) == [0.125])
            #expect(reader.string(directory[4]) == "ILCE")
        }
    }
}
