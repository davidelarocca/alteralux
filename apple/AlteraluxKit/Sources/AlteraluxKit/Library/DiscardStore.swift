import CryptoKit
import Foundation

/// Keeps the "discarded" mark of a photo, where it follows the photo.
///
/// Discarding does not delete: it marks the photo, the library hides it, and the file goes to
/// the Trash only when the user empties the discarded photos. The mark is an extended attribute
/// of the photo itself, like its adjustments (ADR 0008): it travels with the file and changes
/// neither its pixels nor its date. A photo that cannot be written is marked in a folder of the
/// app's instead, under its path.
public struct DiscardStore: Sendable {
    /// The extended attribute that marks a discarded photo. The `#S` suffix asks the system to
    /// keep it when the file is synced.
    static let attributeName = "io.github.davidelarocca.alteralux.discarded#S"

    private let fallbackDirectory: URL

    /// - Parameter fallbackDirectory: where the marks of photos that cannot be written are kept.
    ///   Created when first needed.
    public init(fallbackDirectory: URL) {
        self.fallbackDirectory = fallbackDirectory
    }

    /// Whether the photo at `url` is marked as discarded.
    public func isDiscarded(_ url: URL) -> Bool {
        let inPhoto = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return getxattr(path, Self.attributeName, nil, 0, 0, 0) >= 0
        }
        return inPhoto || FileManager.default.fileExists(atPath: fallbackFile(for: url).path)
    }

    /// Marks the photo at `url` as discarded, or takes the mark away.
    public func setDiscarded(_ discarded: Bool, for url: URL) throws {
        let fallback = fallbackFile(for: url)
        if discarded {
            let marked = url.withUnsafeFileSystemRepresentation { path -> Bool in
                guard let path else { return false }
                return setxattr(path, Self.attributeName, nil, 0, 0, 0) == 0
            }
            if marked {
                try? FileManager.default.removeItem(at: fallback)
            } else {
                try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
                try Data().write(to: fallback, options: .atomic)
            }
        } else {
            url.withUnsafeFileSystemRepresentation { path in
                if let path {
                    _ = removexattr(path, Self.attributeName, 0)
                }
            }
            try? FileManager.default.removeItem(at: fallback)
            if isDiscarded(url) {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
    }

    /// The file that marks a photo that cannot be written: named after the photo's path.
    func fallbackFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return fallbackDirectory.appendingPathComponent(name).appendingPathExtension("discarded")
    }
}
