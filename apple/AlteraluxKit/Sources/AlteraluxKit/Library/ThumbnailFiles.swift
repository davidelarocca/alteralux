import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The files of the thumbnails kept on disk: JPEGs named by a hash of what they were made from,
/// pruned oldest first. Shared by the camera's thumbnails and the developed ones.
enum ThumbnailFiles {
    /// Reads a thumbnail kept on disk, decoded at once.
    static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                  source,
                  0,
                  [kCGImageSourceShouldCacheImmediately: true] as CFDictionary,
              )
        else {
            return nil
        }
        return image
    }

    /// The image as a JPEG, or `nil` when it cannot be written.
    static func jpegData(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary,
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The path, size and modification date of a file, so a thumbnail made from it is not used
    /// once the file changes; `nil` when the file cannot be read.
    static func identity(of url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modificationDate = values.contentModificationDate,
              let fileSize = values.fileSize
        else {
            return nil
        }

        let path = Data(url.path.utf8).base64EncodedString()
        let dateBits = String(modificationDate.timeIntervalSince1970.bitPattern, radix: 16)
        return "\(path)|\(dateBits)|\(fileSize)"
    }

    /// Keeps the thumbnails in `directory` under `limit` bytes, removing the ones written longest
    /// ago. Synchronous: call it off the main thread.
    static func prune(_ directory: URL, toAtMost limit: Int64) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys),
        ) else { return }
        var thumbnails = files.filter { $0.pathExtension == "jpg" }.map { file in
            let values = try? file.resourceValues(forKeys: keys)
            return (file: file, size: Int64(values?.fileSize ?? 0), date: values?.contentModificationDate ?? .distantPast)
        }
        var total = thumbnails.reduce(0) { $0 + $1.size }
        guard total > limit else { return }
        thumbnails.sort { $0.date < $1.date }
        for thumbnail in thumbnails where total > limit {
            if (try? FileManager.default.removeItem(at: thumbnail.file)) != nil {
                total -= thumbnail.size
            }
        }
    }

    /// A name for a file, the same at every launch.
    static func stableHash(_ value: String) -> String {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 7_809_847_782_465_536_322
        for byte in value.utf8 {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second ^ UInt64(byte)) &* 1_403_555_449_261_977_603
        }
        return String(first, radix: 16) + String(second, radix: 16)
    }
}
