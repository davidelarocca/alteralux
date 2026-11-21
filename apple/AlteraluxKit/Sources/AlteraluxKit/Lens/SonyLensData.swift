import Foundation

/// The lens corrections a Sony camera writes in its RAW files (ARW). ImageIO does not read them.
///
/// They are three tags of signed 16-bit numbers in the directory of the raw image (one of the
/// main directory's SubIFDs, which one depending on the body), each led by its count (ADR 0015):
/// - `0x7037`, distortion: `n`, then `n` values `d`, the factor being `1 + d / 2^14`.
/// - `0x7035`, chromatic aberration: `2n`, then `n` values for red and `n` for blue, each a factor
///   `1 + c / 2^21` of the radius over green's.
/// - `0x7032`, vignetting: `m`, then `m` values `v`, the light kept being
///   `(2^(0.5 - 2^(v / 2^13 - 1)))^2`.
///
/// Knot `i` of `n` lies at the radius `i / (n - 1)` of the half diagonal, as ART reads them. The
/// vignetting is squared as darktable's first reading and ART have it: on a Sigma 56mm it follows
/// lensfun's measurement of the lens, where the reading without the square gives half of it.
/// Older bodies keep the tags only in an enciphered block, which is not read.
enum SonyLensData {
    private static let distortionTag: UInt16 = 0x7037
    private static let aberrationTag: UInt16 = 0x7035
    private static let vignettingTag: UInt16 = 0x7032

    /// The corrections the Sony RAW in `data` carries; `nil` when it is not a Sony RAW, or carries
    /// none that can be read.
    static func read(_ data: Data) -> CameraLensData? {
        guard let reader = TIFFReader(data: data),
              let main = reader.directory(at: reader.firstDirectory),
              reader.string(main[0x010F])?.uppercased().hasPrefix("SONY") == true
        else { return nil }
        // The tags are in the raw image's directory, whichever SubIFD that is.
        let directories = reader.directories(main[0x014A]) + [main]
        func values(of tag: UInt16) -> [Int]? {
            directories.lazy.compactMap { reader.integers($0[tag]) }.first
        }
        return curves(
            distortion: values(of: distortionTag), aberration: values(of: aberrationTag),
            vignetting: values(of: vignettingTag),
        )
    }

    /// The corrections the three tags' values say, each led by its count.
    static func curves(distortion: [Int]?, aberration: [Int]?, vignetting: [Int]?) -> CameraLensData? {
        var geometry: CameraLensData.Geometry?
        if let distortion, let count = distortion.first, (2 ... 16).contains(count), distortion.count > count {
            let radii = knots(count)
            let green = distortion[1 ... count].map { 1 + Double($0) / 16384 }
            var red = green
            var blue = green
            if let aberration, aberration.first == 2 * count, aberration.count > 2 * count {
                red = zip(green, aberration[1 ... count]).map { $0 * (1 + Double($1) / 2_097_152) }
                blue = zip(green, aberration[(count + 1) ... (2 * count)]).map { $0 * (1 + Double($1) / 2_097_152) }
            }
            geometry = CameraLensData.Geometry(radii: radii, red: red, green: green, blue: blue)
        }
        var light: RadialCurve?
        if let vignetting, let count = vignetting.first, (2 ... 16).contains(count), vignetting.count > count {
            let kept = vignetting[1 ... count].map { value in
                let fraction = pow(2, 0.5 - pow(2, Double(value) / 8192 - 1))
                return fraction * fraction
            }
            light = RadialCurve(radii: knots(count), values: kept)
        }
        return CameraLensData(maker: .sony, geometry: geometry, vignetting: light)
    }

    /// The radii of `count` knots, in half diagonals.
    static func knots(_ count: Int) -> [Double] {
        (0 ..< count).map { Double($0) / Double(count - 1) }
    }
}
