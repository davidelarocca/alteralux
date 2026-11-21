import Foundation

/// The lens corrections a Nikon Z camera writes in its RAW files (NEF), as ART reads them
/// (ADR 0015; reverse engineered on discuss.pixls.us).
///
/// They are in tag `0xC7D5` of the raw image's directory: "Nikon\0", four bytes of version, then a
/// TIFF structure whose entries 5, 6 and 7 hold the distortion, the vignetting and the fringes.
/// Each has, at byte 0x10, a count `n` and `n` signed rationals `c`, then one more, read as the
/// polynomial `1 + c[0] r^n + c[1] r^(n-1) + ... + c[n-1] r`, `r` in half diagonals of the picture
/// recorded. Distortion: the factor from the corrected radius to the shot one. Vignetting: the gain
/// that lifts it. Fringes: two sets, red then blue, each adding its last rational.
enum NikonLensData {
    static func read(_ data: Data) -> CameraLensData? {
        guard let reader = TIFFReader(data: data),
              let main = reader.directory(at: reader.firstDirectory),
              reader.string(main[0x010F])?.uppercased().hasPrefix("NIKON") == true,
              let entry = (reader.directories(main[0x014A]) + [main]).lazy.compactMap({ $0[0xC7D5] }).first
        else { return nil }
        return curves(blob: reader.bytes(entry))
    }

    /// The corrections in the `0xC7D5` blob.
    static func curves(blob: Data) -> CameraLensData? {
        let blob = Data(blob)
        guard blob.count > 18, blob.starts(with: Array("Nikon\0".utf8)),
              let reader = TIFFReader(data: blob, base: 10),
              let directory = reader.directory(at: reader.firstDirectory)
        else { return nil }

        func sets(_ tag: UInt16, count: Int) -> [(terms: [Double], last: Double)]? {
            guard let entry = directory[tag], entry.count > 0x14 else { return nil }
            var position = entry.valueOffset + 0x10
            let end = entry.valueOffset + entry.count
            var result: [(terms: [Double], last: Double)] = []
            for _ in 0 ..< count {
                guard let terms = reader.unsigned(at: position, size: 4), (1 ... 32).contains(terms),
                      position + 4 + 8 * (terms + 1) <= end
                else { return nil }
                position += 4
                let values = (0 ... terms).map { index -> Double in
                    let offset = position + 8 * index
                    let numerator = reader.unsigned(at: offset, size: 4).map { Int(Int32(truncatingIfNeeded: $0)) } ?? 0
                    let denominator = reader.unsigned(at: offset + 4, size: 4).map { Int(Int32(truncatingIfNeeded: $0)) } ?? 0
                    return denominator == 0 ? 0 : Double(numerator) / Double(denominator)
                }
                position += 8 * (terms + 1)
                result.append((Array(values.dropLast()), values[terms]))
            }
            return result
        }

        let distortion = sets(5, count: 1)?.first?.terms
        let vignetting = sets(6, count: 1)?.first?.terms
        let fringes = sets(7, count: 2)

        var geometry: CameraLensData.Geometry?
        if let distortion, distortion.contains(where: { $0 != 0 }) {
            let green = RadialCurve(sampling: { polynomial(distortion, at: $0) })
            if let fringes, fringes.count == 2 {
                geometry = CameraLensData.Geometry(
                    red: RadialCurve(sampling: { polynomial(distortion, at: $0) * (fringes[0].last + polynomial(fringes[0].terms, at: $0)) }),
                    green: green,
                    blue: RadialCurve(sampling: { polynomial(distortion, at: $0) * (fringes[1].last + polynomial(fringes[1].terms, at: $0)) }),
                )
            } else {
                geometry = CameraLensData.Geometry(distortion: green)
            }
        }
        let light = vignetting.flatMap { terms -> RadialCurve? in
            guard terms.contains(where: { $0 != 0 }) else { return nil }
            return RadialCurve(sampling: { radius in
                let gain = polynomial(terms, at: radius)
                return gain > 0 ? 1 / gain : 1
            })
        }
        return CameraLensData(maker: .nikon, geometry: geometry, vignetting: light)
    }

    /// `1 + c[0] r^n + ... + c[n-1] r`.
    static func polynomial(_ terms: [Double], at radius: Double) -> Double {
        1 + terms.reduce(0) { $0 * radius + $1 } * radius
    }
}
