import Foundation
import ImageIO

/// A DNG with a fault the system's decoders refuse, mended in memory so the photo opens. The file
/// on disk is never changed.
///
/// The DJI Osmo Action writes the DNG version and the oldest version able to read the file (tags
/// 50706 and 50707) as five bytes, where the format has four. Core Image and ImageIO then take
/// the file for no DNG at all: it has no pixels and no size. Mended, each of the two tags keeps
/// its first four bytes, and everything else is as the camera wrote it.
enum MendedDNG {
    /// The bytes of the file at `url` with its version tags mended; `nil` when the file is not a
    /// DNG with that fault, which is nearly always, or cannot be read.
    ///
    /// Telling costs a read of the file's first directory, a few hundred bytes; only a file with
    /// the fault is read whole.
    static func data(for url: URL) -> Data? {
        guard url.pathExtension.lowercased() == "dng", let faults = faults(in: url), !faults.isEmpty,
              var data = try? Data(contentsOf: url)
        else { return nil }
        for fault in faults {
            guard fault.values + 4 <= data.count, fault.entry + 12 <= data.count else { return nil }
            let kept = Data(data[data.startIndex + fault.values ..< data.startIndex + fault.values + 4])
            let count = fault.littleEndian ? Data([4, 0, 0, 0]) : Data([0, 0, 0, 4])
            data.replaceSubrange(data.startIndex + fault.entry + 4 ..< data.startIndex + fault.entry + 8, with: count)
            data.replaceSubrange(data.startIndex + fault.entry + 8 ..< data.startIndex + fault.entry + 12, with: kept)
        }
        return data
    }

    /// The image source of the file at `url`: of its mended bytes when it has the fault.
    static func imageSource(for url: URL) -> CGImageSource? {
        if let data = data(for: url) {
            let options = [kCGImageSourceTypeIdentifierHint: typeIdentifier] as CFDictionary
            return CGImageSourceCreateWithData(data as CFData, options)
        }
        return CGImageSourceCreateWithURL(url as CFURL, nil)
    }

    /// What tells the decoders a mended file is a DNG, since its bytes come with no name.
    static let typeIdentifier = "com.adobe.raw-image"

    /// A version tag longer than four bytes: where its entry is in the file, and where its bytes.
    private struct Fault {
        let entry: Int
        let values: Int
        let littleEndian: Bool
    }

    private static let versionTags: Set<UInt16> = [50706, 50707]
    private static let byteType: UInt16 = 1

    /// The version tags of the first directory that are longer than the format allows; `nil` when
    /// the file is not a TIFF structure or cannot be read.
    private static func faults(in url: URL) -> [Fault]? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 8), header.count == 8 else { return nil }
        let littleEndian: Bool
        switch (header[header.startIndex], header[header.startIndex + 1]) {
        case (0x49, 0x49): littleEndian = true
        case (0x4D, 0x4D): littleEndian = false
        default: return nil
        }
        func number(_ data: Data, at offset: Int, size: Int) -> Int {
            var value = 0
            for index in 0 ..< size {
                let byte = Int(data[data.startIndex + offset + (littleEndian ? size - 1 - index : index)])
                value = value << 8 | byte
            }
            return value
        }
        guard number(header, at: 2, size: 2) == 42 else { return nil }
        let directory = number(header, at: 4, size: 4)
        guard (try? file.seek(toOffset: UInt64(directory))) != nil,
              let countBytes = try? file.read(upToCount: 2), countBytes.count == 2
        else { return nil }
        let count = number(countBytes, at: 0, size: 2)
        guard count > 0, count < 2000, let entries = try? file.read(upToCount: count * 12), entries.count == count * 12
        else { return nil }

        var found: [Fault] = []
        for index in 0 ..< count {
            let start = index * 12
            let tag = UInt16(number(entries, at: start, size: 2))
            guard versionTags.contains(tag), number(entries, at: start + 2, size: 2) == Int(byteType),
                  number(entries, at: start + 4, size: 4) > 4
            else { continue }
            found.append(Fault(
                entry: directory + 2 + start, values: number(entries, at: start + 8, size: 4), littleEndian: littleEndian,
            ))
        }
        return found
    }
}
