import Foundation

/// Builds small TIFF structures for the tests of the lens correction readers: directories of
/// entries, nested as the RAW files and their maker notes nest them.
struct TIFFBuilder {
    indirect enum Value {
        case ascii(String)
        case shorts([Int])
        case signedShorts([Int])
        case longs([Int])
        case signedRationals([Double])
        case floats([Double])
        case bytes([UInt8])
        /// Offsets of directories written before this one (SubIFDs, 0x8769, 0xF000).
        case directories([Directory])
    }

    struct Directory {
        var entries: [(tag: UInt16, value: Value)]
    }

    let littleEndian: Bool
    /// The magic number after the byte order: 42, or Panasonic's 0x55.
    var magic = 42

    /// The bytes of a TIFF whose first directory is `root`.
    func build(_ root: Directory) -> [UInt8] {
        var bytes: [UInt8] = littleEndian ? [0x49, 0x49] : [0x4D, 0x4D]
        bytes += encode(magic, 2)
        bytes += encode(0, 4)
        let offset = write(root, into: &bytes)
        bytes.replaceSubrange(4 ..< 8, with: encode(offset, 4))
        return bytes
    }

    /// One entry ready to write: its type, its number of values and their bytes.
    private struct Resolved {
        let tag: UInt16
        let type: Int
        let count: Int
        let payload: [UInt8]
    }

    /// Writes `directory` (and the ones it points at, first) at the end of `bytes`, offsets
    /// counted from the start of `bytes`; returns where the directory is.
    func write(_ directory: Directory, into bytes: inout [UInt8]) -> Int {
        let resolved = directory.entries.sorted { $0.tag < $1.tag }.map { resolve($0.tag, $0.value, into: &bytes) }
        if bytes.count % 2 == 1 {
            bytes.append(0)
        }
        let start = bytes.count
        var data = start + 2 + resolved.count * 12 + 4
        var tail: [UInt8] = []
        bytes += encode(resolved.count, 2)
        for entry in resolved {
            bytes += encode(Int(entry.tag), 2) + encode(entry.type, 2) + encode(entry.count, 4)
            if entry.payload.count <= 4 {
                bytes += entry.payload + [UInt8](repeating: 0, count: 4 - entry.payload.count)
            } else {
                bytes += encode(data, 4)
                tail += entry.payload
                data += entry.payload.count
            }
        }
        bytes += encode(0, 4)
        bytes += tail
        return start
    }

    private func resolve(_ tag: UInt16, _ value: Value, into bytes: inout [UInt8]) -> Resolved {
        switch value {
        case let .ascii(text):
            let payload = Array(text.utf8) + [0]
            return Resolved(tag: tag, type: 2, count: payload.count, payload: payload)
        case let .shorts(values):
            return Resolved(tag: tag, type: 3, count: values.count, payload: values.flatMap { encode($0, 2) })
        case let .signedShorts(values):
            return Resolved(tag: tag, type: 8, count: values.count, payload: values.flatMap { encode($0, 2) })
        case let .longs(values):
            return Resolved(tag: tag, type: 4, count: values.count, payload: values.flatMap { encode($0, 4) })
        case let .signedRationals(values):
            let payload = values.flatMap { encode(Int(($0 * 1_000_000).rounded()), 4) + encode(1_000_000, 4) }
            return Resolved(tag: tag, type: 10, count: values.count, payload: payload)
        case let .floats(values):
            return Resolved(tag: tag, type: 11, count: values.count, payload: values.flatMap { encode(Int(Float($0).bitPattern), 4) })
        case let .bytes(values):
            return Resolved(tag: tag, type: 7, count: values.count, payload: values)
        case let .directories(children):
            let offsets = children.map { write($0, into: &bytes) }
            return Resolved(tag: tag, type: 4, count: offsets.count, payload: offsets.flatMap { encode($0, 4) })
        }
    }

    func encode(_ value: Int, _ size: Int) -> [UInt8] {
        let ordered = (0 ..< size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        return littleEndian ? ordered : ordered.reversed()
    }
}
