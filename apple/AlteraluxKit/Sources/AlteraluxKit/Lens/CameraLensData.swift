import Foundation

/// A quantity that depends only on the distance from the center of the picture: values at
/// increasing radii (in half diagonals), with straight lines between them, and the first or the
/// last value before the first radius or past the last.
public struct RadialCurve: Sendable, Equatable {
    public let radii: [Double]
    public let values: [Double]

    /// A curve through `values` at `radii`; `nil` unless there are as many of both, at least one,
    /// and the radii increase.
    public init?(radii: [Double], values: [Double]) {
        guard !radii.isEmpty, radii.count == values.count,
              zip(radii, radii.dropFirst()).allSatisfy({ $0 < $1 }),
              (radii + values).allSatisfy(\.isFinite)
        else { return nil }
        self.radii = radii
        self.values = values
    }

    /// `function` read at `count` radii evenly spread from 0 to `last`: how the corrections the
    /// cameras record as polynomials become curves. With the default 257 points the straight lines
    /// stay within a millionth of the polynomials of the cameras measured.
    public init(sampling function: (Double) -> Double, upTo last: Double = 1.6, count: Int = 257) {
        radii = (0 ..< count).map { last * Double($0) / Double(count - 1) }
        values = radii.map(function)
    }

    /// The same value at every radius.
    public static func constant(_ value: Double) -> RadialCurve {
        RadialCurve(sampling: { _ in value }, upTo: 1, count: 2)
    }

    /// The value at `radius`, in half diagonals.
    public func value(at radius: Double) -> Double {
        guard radius > radii[0] else { return values[0] }
        guard radius < radii[radii.count - 1] else { return values[values.count - 1] }
        // Binary search for the segment that holds the radius.
        var low = 0
        var high = radii.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if radii[middle] <= radius {
                low = middle
            } else {
                high = middle
            }
        }
        let fraction = (radius - radii[low]) / (radii[high] - radii[low])
        return values[low] + (values[high] - values[low]) * fraction
    }

    /// Whether every value is `value`.
    func isEverywhere(_ value: Double) -> Bool {
        values.allSatisfy { abs($0 - value) < 1e-9 }
    }
}

/// Who made the camera whose corrections a file carries: what decides how Apple's RAW decoder
/// treats them.
public enum CameraMaker: String, Sendable, Equatable {
    case sony, fujifilm, nikon, olympus, panasonic

    /// Whether Apple's decoder lifts the vignetting itself, from what the camera recorded, for a
    /// photo whose lens it corrects. Measured on 2026-11-21 against the sensor's own values, read
    /// from the files: it does for Nikon (with its lens correction on or off), and does not for
    /// Sony or Fujifilm. Olympus and Panasonic record no vignetting.
    var appleLiftsVignetting: Bool {
        self == .nikon
    }
}

/// The lens corrections a camera recorded in a RAW file, as radial curves (ADR 0015): for the
/// lens on the camera at the moment of the shot, whoever made it, as long as it talks to the
/// camera. Each maker writes them its own way; `read(from:)` finds the reader for the file.
public struct CameraLensData: Sendable, Equatable {
    /// The geometry, for each channel: the factor by which the radius of a point of the corrected
    /// picture is multiplied to find where it comes from in the photo as shot. Green holds the
    /// distortion; red and blue also move apart from it to take away the colored fringes. `nil`
    /// when the camera recorded none.
    public struct Geometry: Sendable, Equatable {
        public let red: RadialCurve
        public let green: RadialCurve
        public let blue: RadialCurve

        public init(red: RadialCurve, green: RadialCurve, blue: RadialCurve) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The three curves through the values of each channel at `radii`; `nil` when they do not
        /// make curves.
        init?(radii: [Double], red: [Double], green: [Double], blue: [Double]) {
            guard let red = RadialCurve(radii: radii, values: red),
                  let green = RadialCurve(radii: radii, values: green),
                  let blue = RadialCurve(radii: radii, values: blue)
            else { return nil }
            self.init(red: red, green: green, blue: blue)
        }

        /// The distortion alone, the same for the three channels.
        public init(distortion: RadialCurve) {
            self.init(red: distortion, green: distortion, blue: distortion)
        }

        /// The curve of `channel`: 0 red, 1 green, 2 blue.
        func curve(_ channel: Int) -> RadialCurve {
            channel == 0 ? red : channel == 2 ? blue : green
        }

        var isIdentity: Bool {
            [red, green, blue].allSatisfy { $0.isEverywhere(1) }
        }
    }

    public let maker: CameraMaker
    public let geometry: Geometry?
    /// The fraction of the light the lens lets through, by the radius in the photo as shot: 1 at
    /// the center, less towards the corners. `nil` when the camera recorded none.
    public let vignetting: RadialCurve?

    /// What a camera recorded, with nothing left that corrects nothing; `nil` when nothing does.
    public init?(maker: CameraMaker, geometry: Geometry?, vignetting: RadialCurve?) {
        self.maker = maker
        self.geometry = geometry.flatMap { $0.isIdentity ? nil : $0 }
        self.vignetting = vignetting.flatMap { $0.isEverywhere(1) ? nil : $0 }
        guard self.geometry != nil || self.vignetting != nil else { return nil }
    }

    /// The corrections the RAW at `url` carries, for the makers whose readings are known: Sony
    /// (ARW), Fujifilm (RAF), Nikon Z (NEF), Olympus and OM System (ORF), Panasonic (RW2). `nil`
    /// for other files, and for files that carry none. Canon writes none that can be read; DNG
    /// files carry theirs as opcodes, which Apple's decoder applies itself.
    public static func read(from url: URL) -> CameraLensData? {
        let reader: ((Data) -> CameraLensData?)? = switch url.pathExtension.lowercased() {
        case "arw", "sr2": SonyLensData.read
        case "raf": FujifilmLensData.read
        case "nef", "nrw": NikonLensData.read
        case "orf", "ori": OlympusLensData.read
        case "rw2", "rwl": PanasonicLensData.read
        default: nil
        }
        guard let reader, let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return reader(data)
    }
}
