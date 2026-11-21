import Foundation
import ImageIO

/// What a photo says about the camera and the lens it was taken with, as far as a lens profile
/// needs: read from the file's metadata, for RAW files too, without decoding any pixels.
public struct PhotoLensInfo: Sendable, Equatable {
    /// The camera's maker, as the file spells it ("SONY", "Canon").
    public var cameraMaker: String
    /// The camera's model ("ILCE-7M3").
    public var cameraModel: String
    /// The lens's model as the file names it; empty for cameras with a fixed lens.
    public var lensModel: String
    /// The focal length in millimeters.
    public var focalLength: Double
    /// The aperture as an f-number; 0 when the file does not say.
    public var aperture: Double
    /// The focus distance in meters, when the file says.
    public var focusDistance: Double?

    public init(
        cameraMaker: String,
        cameraModel: String,
        lensModel: String,
        focalLength: Double,
        aperture: Double,
        focusDistance: Double? = nil,
    ) {
        self.cameraMaker = cameraMaker
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.aperture = aperture
        self.focusDistance = focusDistance
    }

    /// The lens information of the photo at `url`, or `nil` when the file does not name its camera
    /// or does not give a focal length.
    public static func read(from url: URL) -> PhotoLensInfo? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return nil }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        let model = trimmed(tiff[kCGImagePropertyTIFFModel])
        guard !model.isEmpty, let focalLength = number(exif[kCGImagePropertyExifFocalLength]), focalLength > 0 else {
            return nil
        }
        var lensModel = trimmed(exif[kCGImagePropertyExifLensModel])
        if lensModel.isEmpty {
            lensModel = trimmed(aux[kCGImagePropertyExifAuxLensModel])
        }
        let distance = number(exif[kCGImagePropertyExifSubjectDistance])
        return PhotoLensInfo(
            cameraMaker: trimmed(tiff[kCGImagePropertyTIFFMake]),
            cameraModel: model,
            lensModel: lensModel,
            focalLength: focalLength,
            aperture: number(exif[kCGImagePropertyExifFNumber]) ?? 0,
            focusDistance: distance.flatMap { $0 > 0 ? $0 : nil },
        )
    }

    private static func trimmed(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
