import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How to write an exported photo.
public struct ExportOptions: Sendable, Equatable, Codable {
    public enum Format: String, Sendable, CaseIterable, Codable {
        /// 8-bit JPEG: the most compatible choice.
        case jpeg
        /// 10-bit HEIC: smaller files, smoother gradients.
        case heic
        /// 16-bit TIFF: lossless, for further editing or printing.
        case tiff
        /// 16-bit PNG: lossless.
        case png

        public var contentType: UTType {
            switch self {
            case .jpeg: .jpeg
            case .heic: .heic
            case .tiff: .tiff
            case .png: .png
            }
        }

        public var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            case .heic: "heic"
            case .tiff: "tif"
            case .png: "png"
            }
        }
    }

    public enum ColorProfile: String, Sendable, CaseIterable, Codable {
        /// Safe everywhere, including the web.
        case sRGB
        /// The native gamut of Apple displays.
        case displayP3
    }

    public var format: Format
    public var colorProfile: ColorProfile
    /// Compression quality for JPEG and HEIC, from 0 to 1.
    public var quality: Double
    /// Copy camera metadata (EXIF, lens, date, location) from the original.
    public var copiesMetadata: Bool
    /// The long side of the exported photo, in pixels. `nil` for the size of the original.
    public var longSide: Int?

    public init(
        format: Format = .jpeg, colorProfile: ColorProfile = .sRGB, quality: Double = 0.92,
        copiesMetadata: Bool = true, longSide: Int? = nil,
    ) {
        self.format = format
        self.colorProfile = colorProfile
        self.quality = quality
        self.copiesMetadata = copiesMetadata
        self.longSide = longSide
    }
}

/// Writes developed photos to disk with correct color management.
public enum ImageExporter {
    /// Writes `image` to `url`.
    ///
    /// The engine's display-linear pixels are converted by Core Image to the
    /// chosen output profile, which is embedded in the file.
    ///
    /// - Parameter originalURL: the source photo, to copy its metadata from.
    public static func write(
        _ image: DevelopedImage, to url: URL, options: ExportOptions = ExportOptions(),
        originalURL: URL? = nil,
    ) throws {
        var ciImage = CIImage(cgImage: image.cgImage)
        if options.copiesMetadata, let originalURL {
            ciImage = ciImage.settingProperties(metadata(from: originalURL))
        }
        let colorSpace = cgColorSpace(for: options.colorProfile)
        let quality: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(
                rawValue: kCGImageDestinationLossyCompressionQuality as String,
            ): options.quality,
        ]
        do {
            switch options.format {
            case .jpeg:
                try context.writeJPEGRepresentation(
                    of: ciImage, to: url, colorSpace: colorSpace, options: quality,
                )
            case .heic:
                try context.writeHEIF10Representation(
                    of: ciImage, to: url, colorSpace: colorSpace, options: quality,
                )
            case .tiff:
                try context.writeTIFFRepresentation(
                    of: ciImage, to: url, format: .RGBA16, colorSpace: colorSpace, options: [:],
                )
            case .png:
                try context.writePNGRepresentation(
                    of: ciImage, to: url, format: .RGBA16, colorSpace: colorSpace, options: [:],
                )
            }
        } catch {
            throw AlteraluxError.exportFailed(error.localizedDescription)
        }
    }

    static func cgColorSpace(for profile: ExportOptions.ColorProfile) -> CGColorSpace {
        switch profile {
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }

    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        .workingFormat: NSNumber(value: CIFormat.RGBAf.rawValue),
        .cacheIntermediates: false,
    ])

    /// Descriptive metadata of the original, without the keys that describe
    /// its pixels (size, orientation, color), which no longer apply.
    static func metadata(from url: URL) -> [String: Any] {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let all = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [:] }

        var result: [String: Any] = [:]
        let copiedDictionaries = [
            kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
        ]
        for key in copiedDictionaries {
            if let value = all[key as String] {
                result[key as String] = value
            }
        }
        if var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
            exif.removeValue(forKey: kCGImagePropertyExifColorSpace as String)
            result[kCGImagePropertyExifDictionary as String] = exif
        }
        var tiff: [String: Any] = [:]
        if let original = all[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            let copiedKeys = [
                kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel,
                kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFArtist,
                kCGImagePropertyTIFFCopyright,
            ]
            for key in copiedKeys {
                if let value = original[key as String] {
                    tiff[key as String] = value
                }
            }
        }
        tiff[kCGImagePropertyTIFFSoftware as String] = "alteralux for macOS"
        result[kCGImagePropertyTIFFDictionary as String] = tiff
        return result
    }
}
