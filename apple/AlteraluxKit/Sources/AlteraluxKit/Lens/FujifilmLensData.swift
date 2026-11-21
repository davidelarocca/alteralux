import Foundation

/// The lens corrections a Fujifilm camera writes in its RAW files (RAF), as darktable and ART read
/// them (ADR 0015).
///
/// A RAF starts with a header of big-endian offsets; the one at byte 100 points at a TIFF
/// structure whose directory `0xF000` holds three tables of rationals, each
/// `[scale, n radii, n values]`, the radii being in the photo as shot, in half diagonals:
/// - `0xF00B`, distortion: in percent, the factor from the corrected radius to the shot one
///   being `1 + d / 100`.
/// - `0xF00F`, chromatic aberration: `[scale, m radii, m red, m blue]`, as fractions of the radius,
///   on the same radii or the same without the first.
/// - `0xF010`, vignetting: the light kept, in percent.
///
/// In the 1.25× crop modes of some bodies (the maker note's `CropMode`, 2 or 4), the radii are
/// scaled by 1.25.
enum FujifilmLensData {
    static func read(_ data: Data) -> CameraLensData? {
        guard data.count > 104, data.starts(with: Array("FUJIFILM".utf8)),
              let rawBase = TIFFReader.read(data, at: 100, size: 4, littleEndian: false),
              let reader = TIFFReader(data: data, base: rawBase),
              let main = reader.directory(at: reader.firstDirectory),
              let fujiOffset = reader.integers(main[0xF000])?.first,
              let fuji = reader.directory(at: fujiOffset)
        else { return nil }
        return curves(
            distortion: reader.numbers(fuji[0xF00B]), aberration: reader.numbers(fuji[0xF00F]),
            vignetting: reader.numbers(fuji[0xF010]), cropFactor: cropMode(in: data).map { [2, 4].contains($0) ? 1.25 : 1 } ?? 1,
        )
    }

    /// The corrections the three tables say.
    static func curves(distortion: [Double]?, aberration: [Double]?, vignetting: [Double]?, cropFactor: Double) -> CameraLensData? {
        guard let distortion, distortion.count >= 5, distortion.count % 2 == 1 else { return nil }
        let count = (distortion.count - 1) / 2
        let shotRadii = distortion[1 ... count].map { $0 * cropFactor }
        guard zip(shotRadii, shotRadii.dropFirst()).allSatisfy({ $0 < $1 }), shotRadii[0] >= 0 else { return nil }
        let factors = distortion[(count + 1)...].map { 1 + $0 / 100 }

        // The fringes, at the distortion's radii, from the aberration's own radii.
        var red = [Double](repeating: 1, count: count)
        var blue = red
        if let aberration, let fringes = fringes(aberration, cropFactor: cropFactor) {
            red = shotRadii.map { 1 + fringes.red.value(at: $0) }
            blue = shotRadii.map { 1 + fringes.blue.value(at: $0) }
        }

        // The tables say, for a radius of the photo as shot, by how much the corrected radius was
        // multiplied: move them to the corrected radii, and start from no correction at the
        // center. Between radii the factor goes with the square of the radius, as distortion does.
        let correctedRadii = zip(shotRadii, factors).map { $0 / $1 }
        var squares = correctedRadii.map { $0 * $0 }
        var greenValues = factors
        var redValues = zip(factors, red).map { $0 * $1 }
        var blueValues = zip(factors, blue).map { $0 * $1 }
        if shotRadii[0] > 0 {
            squares.insert(0, at: 0)
            greenValues.insert(1, at: 0)
            redValues.insert(red[0], at: 0)
            blueValues.insert(blue[0], at: 0)
        } else {
            greenValues[0] = 1
            redValues[0] = red[0]
            blueValues[0] = blue[0]
        }
        // Read in the square of the radius, then as curves in the radius.
        let squared = CameraLensData.Geometry(radii: squares, red: redValues, green: greenValues, blue: blueValues)
        let geometry = squared.map { curves in
            CameraLensData.Geometry(
                red: RadialCurve(sampling: { curves.red.value(at: $0 * $0) }),
                green: RadialCurve(sampling: { curves.green.value(at: $0 * $0) }),
                blue: RadialCurve(sampling: { curves.blue.value(at: $0 * $0) }),
            )
        }

        var light: RadialCurve?
        if let vignetting, vignetting.count == distortion.count {
            var radii = shotRadii
            var kept = vignetting[(count + 1)...].map { max($0, 1) / 100 }
            if radii[0] > 0 {
                radii.insert(0, at: 0)
                kept.insert(1, at: 0)
            }
            light = RadialCurve(radii: radii, values: kept)
        }
        return CameraLensData(maker: .fujifilm, geometry: geometry, vignetting: light)
    }

    /// The red and blue fringes of the aberration table, as fractions of the radius, by the radius
    /// in the photo as shot: its radii are the distortion's, or the same without the first, and a
    /// value may follow.
    static func fringes(_ table: [Double], cropFactor: Double) -> (red: RadialCurve, blue: RadialCurve)? {
        for count in stride(from: (table.count - 1) / 3, through: 2, by: -1) where (1 + 3 * count ... 2 + 3 * count).contains(table.count) {
            let radii = table[1 ... count].map { $0 * cropFactor }
            guard let red = RadialCurve(radii: radii, values: Array(table[(count + 1) ... (2 * count)])),
                  let blue = RadialCurve(radii: radii, values: Array(table[(2 * count + 1) ... (3 * count)]))
            else { continue }
            return (red, blue)
        }
        return nil
    }

    /// The maker note's `CropMode` (0x104D), in the EXIF of the JPEG preview the RAF holds.
    static func cropMode(in data: Data) -> Int? {
        guard let jpegStart = TIFFReader.read(data, at: 84, size: 4, littleEndian: false),
              let jpegLength = TIFFReader.read(data, at: 88, size: 4, littleEndian: false),
              jpegStart > 0, jpegStart + jpegLength <= data.count
        else { return nil }
        let window = data[(data.startIndex + jpegStart) ..< (data.startIndex + min(jpegStart + jpegLength, jpegStart + 65536))]
        guard let exif = window.firstRange(of: Data("Exif\0\0".utf8)),
              let reader = TIFFReader(data: data, base: exif.upperBound - data.startIndex),
              let main = reader.directory(at: reader.firstDirectory),
              let exifOffset = reader.integers(main[0x8769])?.first,
              let exifDirectory = reader.directory(at: exifOffset),
              let note = exifDirectory[0x927C]
        else { return nil }
        let noteBase = reader.base + note.valueOffset
        guard data.count > noteBase + 12,
              data[(data.startIndex + noteBase) ..< (data.startIndex + noteBase + 8)].elementsEqual("FUJIFILM".utf8),
              let directoryOffset = TIFFReader.read(data, at: noteBase + 8, size: 4, littleEndian: true)
        else { return nil }
        let maker = TIFFReader(data: data, base: noteBase, littleEndian: true)
        return maker.directory(at: directoryOffset).flatMap { maker.integers($0[0x104D])?.first }
    }
}
