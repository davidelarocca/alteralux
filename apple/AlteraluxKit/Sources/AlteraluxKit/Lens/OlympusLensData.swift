import Foundation

/// The lens corrections an Olympus or OM System camera writes in its RAW files (ORF), as
/// darktable reads them (ADR 0015): distortion and fringes, no vignetting.
///
/// They are in the maker note's ImageProcessing directory (`0x2040`), as floats:
/// - `0x150A`: `k2, k4, k6, s`. The radius of a point of the corrected picture (1 at the corner)
///   becomes `r s (1 + k2 (r s)^2 + k4 (r s)^4 + k6 (r s)^6)` in the photo as shot.
/// - `0x150C`: `r0, r2, r4, b0, b2, b4`. Red, at the shot radius `R`, moves out by
///   `R (r0 + r2 R^2 + r4 R^4)`; blue likewise.
enum OlympusLensData {
    static func read(_ data: Data) -> CameraLensData? {
        guard let reader = TIFFReader(data: data),
              let main = reader.directory(at: reader.firstDirectory),
              let exifOffset = reader.integers(main[0x8769])?.first,
              let exif = reader.directory(at: exifOffset),
              let note = exif[0x927C],
              let maker = makerNote(in: data, at: reader.base + note.valueOffset),
              let processing = imageProcessing(maker)
        else { return nil }
        return curves(distortion: maker.reader.numbers(processing[0x150A]), aberration: maker.reader.numbers(processing[0x150C]))
    }

    /// The maker note at `offset`: "OLYMPUS\0" and its byte order, its offsets counted from its
    /// start, or "OM SYSTEM\0" likewise.
    static func makerNote(in data: Data, at offset: Int) -> (reader: TIFFReader, directory: [UInt16: TIFFReader.Entry])? {
        let start = data.startIndex + offset
        guard data.count > offset + 20 else { return nil }
        // The prefix, then where the byte order is; the directory follows it.
        for (prefix, order) in [("OLYMPUS\0", 8), ("OM SYSTEM\0", 12)] {
            guard data[start ..< start + prefix.utf8.count].elementsEqual(prefix.utf8) else { continue }
            let littleEndian = data[start + order] == 0x49
            let reader = TIFFReader(data: data, base: offset, littleEndian: littleEndian)
            return reader.directory(at: order + 4).map { (reader, $0) }
        }
        return nil
    }

    /// The ImageProcessing directory: pointed at, or held in the entry itself.
    static func imageProcessing(_ maker: (reader: TIFFReader, directory: [UInt16: TIFFReader.Entry])) -> [UInt16: TIFFReader.Entry]? {
        guard let entry = maker.directory[0x2040] else { return nil }
        if entry.type == 4 || entry.type == 13, let offset = maker.reader.integers(entry)?.first {
            return maker.reader.directory(at: offset)
        }
        return maker.reader.directory(at: entry.valueOffset)
    }

    static func curves(distortion: [Double]?, aberration: [Double]?) -> CameraLensData? {
        guard let distortion, distortion.count == 4, distortion[0 ..< 3].contains(where: { $0 != 0 }) else { return nil }
        let (quadratic, quartic, sextic, scale) = (distortion[0], distortion[1], distortion[2], distortion[3])
        func factor(_ radius: Double) -> Double {
            let square = radius * scale * radius * scale
            return scale * (1 + square * (quadratic + square * (quartic + square * sextic)))
        }
        guard let aberration, aberration.count == 6, aberration.contains(where: { $0 != 0 }) else {
            return CameraLensData(maker: .olympus, geometry: .init(distortion: RadialCurve(sampling: factor)), vignetting: nil)
        }
        func fringe(_ radius: Double, _ terms: ArraySlice<Double>) -> Double {
            let terms = Array(terms)
            let shot = factor(radius) * radius
            guard radius > 0 else { return factor(radius) }
            let square = shot * shot
            return factor(radius) + shot * (terms[0] + square * (terms[1] + square * terms[2])) / radius
        }
        let geometry = CameraLensData.Geometry(
            red: RadialCurve(sampling: { fringe($0, aberration[0 ..< 3]) }),
            green: RadialCurve(sampling: factor),
            blue: RadialCurve(sampling: { fringe($0, aberration[3 ..< 6]) }),
        )
        return CameraLensData(maker: .olympus, geometry: geometry, vignetting: nil)
    }
}
