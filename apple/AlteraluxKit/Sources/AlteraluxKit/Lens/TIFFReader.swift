import Foundation

/// Reads the directories of a TIFF structure, as RAW files and their maker notes are, without
/// decoding any image. Offsets are counted from `base`, the start of the structure inside `data`:
/// 0 for a whole file, the start of a maker note or of an embedded TIFF otherwise.
struct TIFFReader {
    struct Entry {
        let type: UInt16
        let count: Int
        /// Where the values are, from `base`: inside the entry when they fit in four bytes.
        let valueOffset: Int
    }

    private let data: Data
    let base: Int
    let littleEndian: Bool
    /// The offset of the first directory, from `base`; 0 when the structure has no header.
    let firstDirectory: Int

    /// A structure that starts with a TIFF header at `base`: "II" or "MM", then 42, or the magic
    /// numbers of Panasonic's RW2 (0x55) and Olympus's ORF ("RO", "RS").
    init?(data: Data, base: Int = 0) {
        guard base >= 0, data.count >= base + 8 else { return nil }
        let start = data.startIndex + base
        switch (data[start], data[start + 1]) {
        case (0x49, 0x49): littleEndian = true
        case (0x4D, 0x4D): littleEndian = false
        default: return nil
        }
        self.data = data
        self.base = base
        let magic = Self.read(data, at: base + 2, size: 2, littleEndian: littleEndian)
        guard let magic, [42, 0x55, 0x4F52, 0x5352, 0x524F, 0x5253].contains(magic) else { return nil }
        firstDirectory = Self.read(data, at: base + 4, size: 4, littleEndian: littleEndian) ?? 0
    }

    /// A structure with no header: a maker note's directory, whose offsets count from `base`.
    init(data: Data, base: Int, littleEndian: Bool) {
        self.data = data
        self.base = base
        self.littleEndian = littleEndian
        firstDirectory = 0
    }

    /// The entries of the directory at `offset`, by tag.
    func directory(at offset: Int) -> [UInt16: Entry]? {
        guard offset > 0, let count = unsigned(at: offset, size: 2), count < 2000 else { return nil }
        var entries: [UInt16: Entry] = [:]
        for index in 0 ..< count {
            let start = offset + 2 + index * 12
            guard let tag = unsigned(at: start, size: 2), let type = unsigned(at: start + 2, size: 2),
                  let valueCount = unsigned(at: start + 4, size: 4)
            else { return nil }
            let size = Self.size(of: UInt16(type)) * valueCount
            let valueOffset = size <= 4 ? start + 8 : unsigned(at: start + 8, size: 4) ?? -1
            guard valueOffset >= 0, base + valueOffset + size <= data.count else { continue }
            entries[UInt16(tag)] = Entry(type: UInt16(type), count: valueCount, valueOffset: valueOffset)
        }
        return entries
    }

    /// The directories an entry points at, as the main directory's SubIFDs (0x014A) do.
    func directories(_ entry: Entry?) -> [[UInt16: Entry]] {
        (integers(entry) ?? []).compactMap { directory(at: $0) }
    }

    /// The values of an entry of whole numbers: unsigned or signed, of 8, 16 or 32 bits.
    func integers(_ entry: Entry?) -> [Int]? {
        guard let entry else { return nil }
        let size = Self.size(of: entry.type)
        let signed: Bool
        switch entry.type {
        case 1, 3, 4, 7, 13: signed = false
        case 6, 8, 9: signed = true
        default: return nil
        }
        return (0 ..< entry.count).compactMap { index in
            integer(at: entry.valueOffset + index * size, size: size, signed: signed)
        }
    }

    /// The values of an entry of numbers of any kind: whole, rational or floating point.
    func numbers(_ entry: Entry?) -> [Double]? {
        guard let entry else { return nil }
        switch entry.type {
        case 5, 10:
            let signed = entry.type == 10
            return (0 ..< entry.count).compactMap { index in
                let offset = entry.valueOffset + index * 8
                guard let numerator = integer(at: offset, size: 4, signed: signed),
                      let denominator = integer(at: offset + 4, size: 4, signed: signed)
                else { return nil }
                return denominator == 0 ? 0 : Double(numerator) / Double(denominator)
            }
        case 11:
            return (0 ..< entry.count).compactMap { index in
                unsigned(at: entry.valueOffset + index * 4, size: 4).map { Double(Float(bitPattern: UInt32(truncatingIfNeeded: $0))) }
            }
        case 12:
            return (0 ..< entry.count).compactMap { index in
                unsigned(at: entry.valueOffset + index * 8, size: 8).map { Double(bitPattern: UInt64(bitPattern: Int64($0))) }
            }
        default:
            return integers(entry)?.map(Double.init)
        }
    }

    /// The text of an entry of type ASCII, without its trailing zeros.
    func string(_ entry: Entry?) -> String? {
        guard let entry, entry.type == 2 else { return nil }
        return String(bytes: bytes(entry).prefix { $0 != 0 }, encoding: .isoLatin1)
    }

    /// The bytes of an entry's values, as they are in the file.
    func bytes(_ entry: Entry) -> Data {
        let start = data.startIndex + base + entry.valueOffset
        let length = Self.size(of: entry.type) * entry.count
        return data[start ..< min(start + length, data.endIndex)]
    }

    /// A number of `size` bytes at `offset` from `base`, in this structure's byte order.
    func unsigned(at offset: Int, size: Int) -> Int? {
        Self.read(data, at: base + offset, size: size, littleEndian: littleEndian)
    }

    private func integer(at offset: Int, size: Int, signed: Bool) -> Int? {
        guard let value = unsigned(at: offset, size: size) else { return nil }
        guard signed else { return value }
        let bits = size * 8
        return value >= 1 << (bits - 1) ? value - (1 << bits) : value
    }

    static func read(_ data: Data, at offset: Int, size: Int, littleEndian: Bool) -> Int? {
        guard offset >= 0, offset + size <= data.count else { return nil }
        let start = data.startIndex + offset
        var value: UInt64 = 0
        for index in 0 ..< size {
            let byte = UInt64(data[start + (littleEndian ? size - 1 - index : index)])
            value = value << 8 | byte
        }
        return Int(truncatingIfNeeded: value)
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
