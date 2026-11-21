import Foundation

/// The distortion a Panasonic camera writes in its RAW files (RW2), as darktable reads it
/// (ADR 0015, after Rigo's notes on the format): no fringes, no vignetting.
///
/// Tag `0x0119` of the main directory holds sixteen little-endian signed 16-bit numbers `v`. With
/// `v[7] & 0xF == 1` the correction is on, and the corrected radius `Ru` of a point at the radius
/// `Rd` in the photo as shot, both in half diagonals, is
/// `Ru = Rd + s (a Rd^3 + b Rd^5 + c Rd^7)`, with `s = 1 / (1 + v[5] / 32768)`,
/// `a = v[8] / 32768`, `b = v[4] / 32768`, `c = v[11] / 32768`.
enum PanasonicLensData {
    static func read(_ data: Data) -> CameraLensData? {
        guard let reader = TIFFReader(data: data),
              let main = reader.directory(at: reader.firstDirectory),
              let entry = main[0x0119], entry.count >= 32
        else { return nil }
        let bytes = Array(reader.bytes(entry).prefix(32))
        let values = (0 ..< 16).map { index -> Int in
            let word = UInt16(bytes[2 * index]) | UInt16(bytes[2 * index + 1]) << 8
            return Int(Int16(bitPattern: word))
        }
        return curves(values)
    }

    static func curves(_ values: [Int]) -> CameraLensData? {
        guard values.count == 16, values[7] & 0xF == 1 else { return nil }
        let scale = 1 / (1 + Double(values[5]) / 32768)
        let cubic = Double(values[8]) / 32768
        let quintic = Double(values[4]) / 32768
        let septic = Double(values[11]) / 32768
        guard cubic != 0 || quintic != 0 || septic != 0 else { return nil }
        // The shot radius of a corrected one, found by repeating `Rd = Ru / (1 + s (a Rd^2 + ...))`.
        let distortion = RadialCurve(sampling: { corrected in
            var shot = corrected
            for _ in 0 ..< 30 {
                let square = shot * shot
                shot = corrected / (1 + scale * square * (cubic + square * (quintic + square * septic)))
            }
            guard corrected > 0 else { return 1 }
            return shot / corrected
        })
        return CameraLensData(maker: .panasonic, geometry: .init(distortion: distortion), vignetting: nil)
    }
}
