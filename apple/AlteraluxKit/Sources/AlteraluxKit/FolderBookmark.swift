import Foundation

/// A folder the user chose, remembered between launches: inside the sandbox, a security-scoped
/// bookmark gives the app the folder again without asking.
public struct FolderBookmark: Codable, Sendable, Equatable {
    public let data: Data
    public let isSecurityScoped: Bool
    /// Where the folder was when the bookmark was made, to name it when it cannot be found.
    public let path: String

    /// A bookmark of `url`, a folder the user chose: security-scoped in the app, a plain one
    /// outside the sandbox (tests), where it still finds reachable folders.
    public init(for url: URL) throws {
        path = url.path
        do {
            data = try url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil,
            )
            isSecurityScoped = true
        } catch {
            data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            isSecurityScoped = false
        }
    }

    /// The folder's name, as the Finder shows it.
    public var name: String {
        FileManager.default.displayName(atPath: path)
    }

    /// The folder now, or `nil` when it cannot be found. The caller starts and stops the
    /// access to it (`startAccessingSecurityScopedResource`).
    public func resolve() -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: isSecurityScoped ? [.withSecurityScope] : [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        )
    }
}
