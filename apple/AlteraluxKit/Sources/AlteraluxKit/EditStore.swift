import CryptoKit
import Foundation

/// Keeps each photo's adjustments between launches, where they follow the photo.
///
/// The adjustments are written into the photo itself, as an extended attribute: the pixels and
/// the modification date are untouched, and the Finder carries the attribute along when the
/// photo is moved, renamed, duplicated or archived. A photo that cannot be written (a read-only
/// disk, a locked card) has its adjustments kept in a folder of the app's instead, under the
/// photo's path. See ADR 0008.
public actor EditStore {
    /// Where a photo's adjustments were written.
    public enum Place: Sendable, Equatable {
        /// In the photo itself.
        case photo
        /// In the app's folder, because the photo could not be written.
        case store
    }

    /// The extended attribute that holds the adjustments. The `#S` suffix marks it as one to
    /// keep when the file is synced (iCloud Drive).
    static let attributeName = "io.github.davidelarocca.alteralux.edit#S"
    /// The version of the stored format. A photo edited by a later version is left alone.
    static let formatVersion = 1

    private nonisolated let fallbackDirectory: URL
    private nonisolated let currentFilmModel: String

    /// - Parameters:
    ///   - fallbackDirectory: where the adjustments of photos that cannot be written are kept.
    ///     Created when first needed.
    ///   - filmModel: the film model written beside the adjustments: the one the app is built
    ///     with, unless a test stands in for another.
    public init(fallbackDirectory: URL, filmModel: String = FilmModel.version) {
        self.fallbackDirectory = fallbackDirectory
        currentFilmModel = filmModel
    }

    /// The adjustments kept for the photo at `url`, if any.
    public nonisolated func load(for url: URL) -> DevelopSettings? {
        stored(for: url)?.settings
    }

    /// The film model the adjustments kept for the photo at `url` were last saved with
    /// (`FilmModel.version` at the time); `nil` when nothing is kept, or when it was kept before
    /// the app wrote the model down.
    public nonisolated func filmModel(for url: URL) -> String? {
        stored(for: url)?.filmModel
    }

    private nonisolated func stored(for url: URL) -> StoredEdit? {
        if let data = Self.attribute(of: url), let stored = Self.decode(data) {
            return stored
        }
        guard let data = try? Data(contentsOf: fallbackFile(for: url)) else { return nil }
        return Self.decode(data)
    }

    /// Whether anything is kept for the photo at `url`: a cheap look, for marking the photos of a
    /// folder that have adjustments without reading them.
    public nonisolated func hasAdjustments(for url: URL) -> Bool {
        let inPhoto = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return getxattr(path, Self.attributeName, nil, 0, 0, 0) > 0
        }
        return inPhoto || FileManager.default.fileExists(atPath: fallbackFile(for: url).path)
    }

    /// Keeps `settings` for the photo at `url`.
    @discardableResult
    public func save(_ settings: DevelopSettings, for url: URL) throws -> Place {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(
            StoredEdit(version: Self.formatVersion, filmModel: currentFilmModel, settings: settings),
        )
        let fallback = fallbackFile(for: url)
        // What a later version of the app wrote into the photo is not this version's to replace:
        // it cannot read it, so it cannot keep what it holds.
        let carriesALaterFormat = Self.attribute(of: url).map { Self.decode($0) == nil && Self.isLaterFormat($0) } ?? false
        if !carriesALaterFormat, Self.setAttribute(data, of: url) {
            // The photo carries its adjustments now: an older copy here would only go stale.
            try? FileManager.default.removeItem(at: fallback)
            return .photo
        }
        try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        try data.write(to: fallback, options: .atomic)
        return .store
    }

    /// Forgets the adjustments kept for the photo at `url`, as if it had never been adjusted.
    ///
    /// What a later version of the app wrote into the photo is not this version's to remove: it
    /// stays in the photo. A photo with nothing kept is not an error; a photo that holds
    /// adjustments but cannot be written (locked, read-only) is.
    public func remove(for url: URL) throws {
        if let data = Self.attribute(of: url), !Self.isLaterFormat(data) {
            try Self.removeAttribute(of: url)
        }
        let fallback = fallbackFile(for: url)
        if FileManager.default.fileExists(atPath: fallback.path) {
            try FileManager.default.removeItem(at: fallback)
        }
    }

    /// The file that holds the adjustments of a photo that cannot be written: named after the
    /// photo's path, which is all that identifies it without writing to it.
    nonisolated func fallbackFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return fallbackDirectory.appendingPathComponent(name).appendingPathExtension("json")
    }

    /// What is written: `{"filmModel": "0.1.2", "settings": {...}, "version": 1}`. The film model
    /// is missing from what was written before the app recorded it.
    private struct StoredEdit: Codable {
        let version: Int
        let filmModel: String?
        let settings: DevelopSettings
    }

    /// What `data` holds, if this version of the app can read it.
    private static func decode(_ data: Data) -> StoredEdit? {
        guard let stored = try? JSONDecoder().decode(StoredEdit.self, from: data) else { return nil }
        return stored.version <= formatVersion ? stored : nil
    }

    /// Whether `data` says it was written in a format later than this version's.
    private static func isLaterFormat(_ data: Data) -> Bool {
        struct Version: Decodable {
            let version: Int
        }
        guard let stored = try? JSONDecoder().decode(Version.self, from: data) else { return false }
        return stored.version > formatVersion
    }

    private static func attribute(of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, attributeName, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, attributeName, $0.baseAddress, size, 0, 0) }
            return read == size ? data : nil
        }
    }

    private static func removeAttribute(of url: URL) throws {
        let failure = url.withUnsafeFileSystemRepresentation { path -> Int32? in
            guard let path else { return EINVAL }
            if removexattr(path, attributeName, 0) == 0 {
                return nil
            }
            // Gone between the look and now: nothing left to remove.
            return errno == ENOATTR ? nil : errno
        }
        if let failure {
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }

    private static func setAttribute(_ data: Data, of url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return data.withUnsafeBytes { setxattr(path, attributeName, $0.baseAddress, data.count, 0, 0) } == 0
        }
    }
}
