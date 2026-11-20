import Foundation

/// Writes a small camera RAW for the tests, so no camera file has to be kept in the repository.
///
/// The file is a linear DNG: a TIFF with the DNG tags and uncompressed 16-bit RGB pixels, which
/// Apple's RAW decoder opens like any DNG. Its camera sees in linear sRGB under daylight and
/// recorded a neutral white balance, so the decoder reports about 6500 K as shot.
///
/// The decoder refuses a RAW that is too small (128 × 96 pixels is, 192 × 128 is not): it
/// gives an image of no size.
enum TestDNG {
    private struct Entry {
        let tag: Int
        let type: Int
        let count: Int
        let payload: Data
    }

    /// TIFF field types.
    private enum FieldType {
        static let byte = 1
        static let ascii = 2
        static let short = 3
        static let long = 4
        static let rational = 5
        static let signedRational = 10
    }

    /// XYZ (D65) to the camera's RGB: here, linear sRGB.
    private static let colorMatrix = [3.2406, -1.5372, -0.4986, -0.9689, 1.8758, 0.0415, 0.0557, -0.2040, 1.0570]

    /// The bytes of a DNG of `width` × `height` pixels: the left half a gray card (18%), the
    /// right half a warm ramp from dark to bright.
    static func grayCard(width: Int = 240, height: Int = 160) -> Data {
        let stripBytes = width * height * 6
        var entries = [
            Entry(tag: 254, type: FieldType.long, count: 1, payload: long(0)), // NewSubFileType
            Entry(tag: 256, type: FieldType.long, count: 1, payload: long(width)),
            Entry(tag: 257, type: FieldType.long, count: 1, payload: long(height)),
            Entry(tag: 258, type: FieldType.short, count: 3, payload: short(16) + short(16) + short(16)),
            Entry(tag: 259, type: FieldType.short, count: 1, payload: short(1)), // uncompressed
            Entry(tag: 262, type: FieldType.short, count: 1, payload: short(34892)), // LinearRaw
            Entry(tag: 271, type: FieldType.ascii, count: 10, payload: ascii("Alteralux")),
            Entry(tag: 272, type: FieldType.ascii, count: 5, payload: ascii("Test")),
            Entry(tag: 273, type: FieldType.long, count: 1, payload: long(0)), // StripOffsets, set below
            Entry(tag: 274, type: FieldType.short, count: 1, payload: short(1)), // Orientation
            Entry(tag: 277, type: FieldType.short, count: 1, payload: short(3)), // SamplesPerPixel
            Entry(tag: 278, type: FieldType.long, count: 1, payload: long(height)), // RowsPerStrip
            Entry(tag: 279, type: FieldType.long, count: 1, payload: long(stripBytes)),
            Entry(tag: 284, type: FieldType.short, count: 1, payload: short(1)), // PlanarConfiguration
            Entry(tag: 50706, type: FieldType.byte, count: 4, payload: Data([1, 4, 0, 0])), // DNGVersion
            Entry(tag: 50707, type: FieldType.byte, count: 4, payload: Data([1, 1, 0, 0])),
            Entry(tag: 50708, type: FieldType.ascii, count: 15, payload: ascii("Alteralux Test")),
            Entry(tag: 50717, type: FieldType.short, count: 3, payload: short(65535) + short(65535) + short(65535)),
            Entry(
                tag: 50721, type: FieldType.signedRational, count: 9,
                payload: colorMatrix.reduce(Data()) { $0 + long(Int(($1 * 10000).rounded())) + long(10000) },
            ),
            // AsShotNeutral: the camera's white is equal parts of its three channels.
            Entry(tag: 50728, type: FieldType.rational, count: 3, payload: (0 ..< 6).reduce(Data()) { data, _ in data + long(1) }),
            Entry(tag: 50778, type: FieldType.short, count: 1, payload: short(21)), // CalibrationIlluminant1: D65
        ]

        // Header, directory, the values too long for the directory, then the pixels.
        let directoryOffset = 8
        let valuesOffset = directoryOffset + 2 + entries.count * 12 + 4
        var values = Data()
        var offsets: [Int: Int] = [:]
        for (index, entry) in entries.enumerated() where entry.payload.count > 4 {
            offsets[index] = valuesOffset + values.count
            values += entry.payload
            if values.count % 2 == 1 {
                values += Data([0])
            }
        }
        let stripIndex = entries.firstIndex { $0.tag == 273 } ?? 0
        entries[stripIndex] = Entry(
            tag: 273, type: FieldType.long, count: 1, payload: long(valuesOffset + values.count),
        )

        var data = Data([0x49, 0x49]) + short(42) + long(directoryOffset)
        data += short(entries.count)
        for (index, entry) in entries.enumerated() {
            data += short(entry.tag) + short(entry.type) + long(entry.count)
            if let offset = offsets[index] {
                data += long(offset)
            } else {
                data += entry.payload + Data(count: 4 - entry.payload.count)
            }
        }
        data += long(0)
        data += values
        data += pixels(width: width, height: height)
        return data
    }

    /// Writes ``grayCard(width:height:)`` to a new temporary file. The caller removes it.
    static func writeGrayCard(width: Int = 240, height: Int = 160) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alteralux-test-\(UUID().uuidString).dng")
        try grayCard(width: width, height: height).write(to: url)
        return url
    }

    private static func pixels(width: Int, height: Int) -> Data {
        var row = Data(capacity: width * 6)
        for column in 0 ..< width {
            if column < width / 2 {
                // 18% of the white level.
                row += short(11796) + short(11796) + short(11796)
            } else {
                let level = 1000 + 50000 * (column - width / 2) / (width / 2)
                row += short(level) + short(level * 8 / 10) + short(level * 6 / 10)
            }
        }
        var data = Data(capacity: row.count * height)
        for _ in 0 ..< height {
            data += row
        }
        return data
    }

    private static func short(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian) { Data($0) }
    }

    private static func long(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) { Data($0) }
    }

    private static func ascii(_ text: String) -> Data {
        Data(text.utf8) + Data([0])
    }
}
