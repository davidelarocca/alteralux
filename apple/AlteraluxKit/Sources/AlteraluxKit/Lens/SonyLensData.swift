import Foundation

/// The lens corrections a Sony camera writes in its RAW files (ARW): for the lens mounted, at the
/// focal length, aperture and distance of the shot, whoever made the lens, as long as it talks to
/// the camera. ImageIO does not read them, so they are read from the file's TIFF structure.
///
/// They are in the first directory under the main one, as three tags of signed 16-bit numbers,
/// each led by its count (ADR 0015; the meaning of the numbers is darktable's reading of them, the
/// vignetting as its first version of it, squared):
/// - `0x7037`, distortion: `n`, then `n` values `d`, the factor being `1 + d / 2^14`.
/// - `0x7035`, chromatic aberration: `2n`, then `n` values for red and `n` for blue, each a factor
///   `1 + c / 2^21` of the radius over green's.
/// - `0x7032`, vignetting: `n`, then `n` values `v`, the light kept being
///   `(2^(0.5 - 2^(v / 2^13 - 1)))^2`.
enum SonyLensData {
    private static let distortionTag: UInt16 = 0x7037
    private static let aberrationTag: UInt16 = 0x7035
    private static let vignettingTag: UInt16 = 0x7032

    /// The four curves, as factors (see `CameraLensCorrection`).
    struct Curves: Equatable {
        let green: [Double]
        let red: [Double]
        let blue: [Double]
        let vignetting: [Double]
    }

    /// The camera's corrections in the RAW at `url`, for its picture of `width` × `height`
    /// pixels, or `nil` when the file is not a Sony RAW that carries them, or carries none.
    static func correction(for url: URL, lensName: String, width: Int, height: Int) -> CameraLensCorrection? {
        guard url.pathExtension.lowercased() == "arw",
              let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let curves = curves(in: data)
        else { return nil }
        return CameraLensCorrection(
            lensName: lensName, green: curves.green, red: curves.red, blue: curves.blue,
            vignetting: curves.vignetting, width: width, height: height,
        )
    }

    /// The curves the file in `data` carries, as factors: `nil` when it is not a Sony RAW, when
    /// a tag is missing or malformed, or when the camera recorded no correction at all.
    static func curves(in data: Data) -> Curves? {
        guard let reader = TIFFReader(data: data),
              let main = reader.directory(at: reader.firstDirectory),
              reader.string(main[0x010F])?.uppercased().hasPrefix("SONY") == true,
              let subOffset = reader.integers(main[0x014A])?.first,
              let raw = reader.directory(at: subOffset),
              let distortion = reader.integers(raw[distortionTag]),
              let aberration = reader.integers(raw[aberrationTag]),
              let vignetting = reader.integers(raw[vignettingTag]),
              let count = distortion.first, (2 ... 16).contains(count),
              distortion.count > count, aberration.first == 2 * count, aberration.count > 2 * count,
              vignetting.first == count, vignetting.count > count
        else { return nil }

        let distortionValues = distortion[1 ... count]
        let redValues = aberration[1 ... count]
        let blueValues = aberration[(count + 1) ... (2 * count)]
        let vignettingValues = vignetting[1 ... count]
        let recordsNothing = [distortionValues, redValues, blueValues, vignettingValues].allSatisfy { values in
            values.allSatisfy { $0 == 0 }
        }
        guard !recordsNothing else { return nil }

        let green = distortionValues.map { 1 + Double($0) / 16384 }
        let red = zip(green, redValues).map { $0 * (1 + Double($1) / 2_097_152) }
        let blue = zip(green, blueValues).map { $0 * (1 + Double($1) / 2_097_152) }
        let light = vignettingValues.map { value in
            let kept = pow(2, 0.5 - pow(2, Double(value) / 8192 - 1))
            return kept * kept
        }
        return Curves(green: green, red: red, blue: blue, vignetting: light)
    }
}

/// Reads the directories of a TIFF file, as RAW files are, without decoding any image.
struct TIFFReader {
    struct Entry {
        let type: UInt16
        let count: Int
        /// Where the values are: inside the entry when they fit in four bytes.
        let valueOffset: Int
    }

    private let data: Data
    private let littleEndian: Bool
    let firstDirectory: Int

    init?(data: Data) {
        guard data.count >= 8 else { return nil }
        self.data = data
        switch (data[data.startIndex], data[data.startIndex + 1]) {
        case (0x49, 0x49): littleEndian = true
        case (0x4D, 0x4D): littleEndian = false
        default: return nil
        }
        guard Self.read(data, at: 2, size: 2, littleEndian: littleEndian) == 42 else { return nil }
        firstDirectory = Self.read(data, at: 4, size: 4, littleEndian: littleEndian) ?? 0
    }

    /// The entries of the directory at `offset`, by tag.
    func directory(at offset: Int) -> [UInt16: Entry]? {
        guard offset > 0, let count = unsigned(at: offset, size: 2) else { return nil }
        var entries: [UInt16: Entry] = [:]
        for index in 0 ..< count {
            let start = offset + 2 + index * 12
            guard let tag = unsigned(at: start, size: 2), let type = unsigned(at: start + 2, size: 2),
                  let valueCount = unsigned(at: start + 4, size: 4)
            else { return nil }
            let size = Self.size(of: UInt16(type)) * valueCount
            let valueOffset = size <= 4 ? start + 8 : unsigned(at: start + 8, size: 4) ?? -1
            guard valueOffset >= 0, valueOffset + size <= data.count else { continue }
            entries[UInt16(tag)] = Entry(type: UInt16(type), count: valueCount, valueOffset: valueOffset)
        }
        return entries
    }

    /// The values of an entry of whole numbers: unsigned or signed, of 8, 16 or 32 bits.
    func integers(_ entry: Entry?) -> [Int]? {
        guard let entry else { return nil }
        let size = Self.size(of: entry.type)
        let signed: Bool
        switch entry.type {
        case 1, 3, 4, 13: signed = false
        case 6, 8, 9: signed = true
        default: return nil
        }
        return (0 ..< entry.count).compactMap { index in
            guard let value = unsigned(at: entry.valueOffset + index * size, size: size) else { return nil }
            guard signed else { return value }
            let bits = size * 8
            return value >= 1 << (bits - 1) ? value - (1 << bits) : value
        }
    }

    /// The text of an entry of type ASCII, without its trailing zeros.
    func string(_ entry: Entry?) -> String? {
        guard let entry, entry.type == 2 else { return nil }
        let start = data.startIndex + entry.valueOffset
        let bytes = data[start ..< start + entry.count].prefix { $0 != 0 }
        return String(bytes: bytes, encoding: .isoLatin1)
    }

    private func unsigned(at offset: Int, size: Int) -> Int? {
        Self.read(data, at: offset, size: size, littleEndian: littleEndian)
    }

    private static func read(_ data: Data, at offset: Int, size: Int, littleEndian: Bool) -> Int? {
        guard offset >= 0, offset + size <= data.count else { return nil }
        let start = data.startIndex + offset
        var value = 0
        for index in 0 ..< size {
            let byte = Int(data[start + (littleEndian ? size - 1 - index : index)])
            value = value << 8 | byte
        }
        return value
    }

    /// The bytes of one value of a TIFF type.
    private static func size(of type: UInt16) -> Int {
        switch type {
        case 3, 8: 2
        case 4, 9, 11, 13: 4
        case 5, 10, 12: 8
        default: 1
        }
    }
}
