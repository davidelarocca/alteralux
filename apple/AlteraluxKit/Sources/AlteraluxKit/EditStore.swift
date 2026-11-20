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

    /// - Parameter fallbackDirectory: where the adjustments of photos that cannot be written are
    ///   kept. Created when first needed.
    public init(fallbackDirectory: URL) {
        self.fallbackDirectory = fallbackDirectory
    }

    /// The adjustments kept for the photo at `url`, if any.
    public nonisolated func load(for url: URL) -> DevelopSettings? {
        if let data = Self.attribute(of: url), let settings = Self.decode(data) {
            return settings
        }
        guard let data = try? Data(contentsOf: fallbackFile(for: url)) else { return nil }
        return Self.decode(data)
    }

    /// Keeps `settings` for the photo at `url`.
    @discardableResult
    public func save(_ settings: DevelopSettings, for url: URL) throws -> Place {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(StoredEdit(version: Self.formatVersion, settings: settings))
        let fallback = fallbackFile(for: url)
        if Self.setAttribute(data, of: url) {
            // The photo carries its adjustments now: an older copy here would only go stale.
            try? FileManager.default.removeItem(at: fallback)
            return .photo
        }
        try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        try data.write(to: fallback, options: .atomic)
        return .store
    }

    /// The file that holds the adjustments of a photo that cannot be written: named after the
    /// photo's path, which is all that identifies it without writing to it.
    nonisolated func fallbackFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return fallbackDirectory.appendingPathComponent(name).appendingPathExtension("json")
    }

    private struct StoredEdit: Codable {
        let version: Int
        let settings: DevelopSettings
    }

    private static func decode(_ data: Data) -> DevelopSettings? {
        guard let stored = try? JSONDecoder().decode(StoredEdit.self, from: data) else { return nil }
        return stored.version <= formatVersion ? stored.settings : nil
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

    private static func setAttribute(_ data: Data, of url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return data.withUnsafeBytes { setxattr(path, attributeName, $0.baseAddress, data.count, 0, 0) } == 0
        }
    }
}
