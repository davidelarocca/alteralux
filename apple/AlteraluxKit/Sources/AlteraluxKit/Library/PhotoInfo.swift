import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// The color of a Finder tag, with the number the Finder stores for it.
public enum FinderTagColor: Int, Sendable, CaseIterable, Codable {
    case gray = 1, green, purple, blue, yellow, red, orange
}

/// A Finder tag a file carries: its name, and its color when it has one.
public struct FinderTag: Sendable, Hashable {
    public let name: String
    public let color: FinderTagColor?

    public init(name: String, color: FinderTagColor? = nil) {
        self.name = name
        self.color = color
    }
}

/// What the library shows and sorts a photo by, read from the file without decoding it.
public struct PhotoInfo: Sendable, Equatable {
    /// Width over height of the photo as it is shown, after the rotation the camera recorded.
    /// 1.5 when the file does not say.
    public let aspectRatio: Double
    /// When the file was created, as the Finder shows it.
    public let date: Date?
    /// Whether the file is a camera RAW.
    public let isRaw: Bool
    /// The size of the file in bytes, when it can be read.
    public let fileSize: Int64?
    /// The Finder tags of the file, in their order.
    public let tags: [FinderTag]

    public init(
        aspectRatio: Double = PhotoInfo.unknownAspectRatio,
        date: Date? = nil,
        isRaw: Bool = false,
        fileSize: Int64? = nil,
        tags: [FinderTag] = [],
    ) {
        self.aspectRatio = aspectRatio
        self.date = date
        self.isRaw = isRaw
        self.fileSize = fileSize
        self.tags = tags
    }

    public static let unknownAspectRatio = 1.5
}

/// Reads `PhotoInfo`. Synchronous and without state: call it off the main thread.
public enum PhotoInfoReader {
    private static let finderTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    /// Reads a photo's library details without decoding its pixels.
    public static func info(of photo: URL) -> PhotoInfo {
        let values = try? photo.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        return PhotoInfo(
            aspectRatio: aspectRatio(of: photo),
            date: values?.creationDate,
            isRaw: ImageLoader.isRawFile(photo),
            fileSize: values?.fileSize.map(Int64.init),
            tags: tags(of: photo),
        )
    }

    /// Reads each photo's details. Files that cannot be read get the default values.
    public static func infos(of photos: [URL]) -> [URL: PhotoInfo] {
        var result: [URL: PhotoInfo] = [:]
        for photo in photos {
            result[photo] = info(of: photo)
        }
        return result
    }

    /// Reads the file's Finder tags and their colors, keeping Finder's order.
    public static func tags(of file: URL) -> [FinderTag] {
        tags(attributeData: finderTagsAttributeData(of: file)) {
            (try? file.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        }
    }

    /// Uses the names supplied by Foundation when the Finder attribute is unavailable or malformed.
    static func tags(attributeData: Data?, fallbackNames: () -> [String]) -> [FinderTag] {
        if let attributeData, let tags = decodeFinderTags(attributeData) {
            return tags
        }

        return fallbackNames().compactMap { name in
            name.isEmpty ? nil : FinderTag(name: name)
        }
    }

    private static func aspectRatio(of photo: URL) -> Double {
        guard
            let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue,
            width > 0,
            height > 0
        else {
            return PhotoInfo.unknownAspectRatio
        }

        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        return (5 ... 8).contains(orientation) ? height / width : width / height
    }

    private static func finderTagsAttributeData(of file: URL) -> Data? {
        file.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, finderTagsAttribute, nil, 0, 0, 0)
            guard size > 0 else { return nil }

            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, finderTagsAttribute, buffer.baseAddress, size, 0, 0)
            }
            return read == size ? data : nil
        }
    }

    private static func decodeFinderTags(_ data: Data) -> [FinderTag]? {
        guard
            let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let values = value as? [String]
        else {
            return nil
        }

        return values.compactMap { value in
            var name = value
            var color: FinderTagColor?
            if let separator = value.lastIndex(of: "\n") {
                let colorNumber = value[value.index(after: separator)...]
                if let number = Int(colorNumber), (0 ... 7).contains(number) {
                    name = String(value[..<separator])
                    color = FinderTagColor(rawValue: number)
                }
            }
            return name.isEmpty ? nil : FinderTag(name: name, color: color)
        }
    }
}
