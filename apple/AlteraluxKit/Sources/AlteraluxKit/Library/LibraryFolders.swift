import Foundation

/// A folder the user has added to the photo library.
public struct LibraryFolder: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let isAvailable: Bool

    public init(id: UUID = UUID(), url: URL, isAvailable: Bool = true) {
        self.id = id
        self.url = url
        self.isAvailable = isAvailable
    }
}

/// Remembers the folders chosen by the user and holds their security-scoped access.
public actor LibraryFolders {
    private struct StoredFolder: Codable {
        var id: UUID
        var bookmarkData: Data
        var isSecurityScoped: Bool
        var lastKnownPath: String
    }

    private struct Entry {
        var folder: LibraryFolder
        var stored: StoredFolder
    }

    private let storeURL: URL
    private var entries: [Entry] = []
    private var accessedURLs: [UUID: URL] = [:]
    private var didLoad = false

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    deinit {
        for url in accessedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Reads saved folders and refreshes any bookmark the system reports as stale.
    public func load() -> [LibraryFolder] {
        do {
            try createStoreDirectory()

            guard FileManager.default.fileExists(atPath: storeURL.path) else {
                stopAccessingAllFolders()
                entries = []
                didLoad = true
                try saveStore()
                return []
            }

            let data = try Data(contentsOf: storeURL)
            let storedFolders = try PropertyListDecoder().decode([StoredFolder].self, from: data)
            stopAccessingAllFolders()

            var refreshedStore = false
            entries = storedFolders.map { stored in
                resolve(stored, refreshedStore: &refreshedStore)
            }
            didLoad = true

            if refreshedStore {
                try? saveStore()
            }
        } catch {
            // Keep the current in-memory list if the store cannot be read.
        }

        return entries.map(\.folder)
    }

    /// Adds a folder, returning its existing entry when it is already remembered.
    @discardableResult
    public func add(_ url: URL) throws -> LibraryFolder {
        loadIfNeeded()

        let standardizedURL = url.standardizedFileURL
        if let existing = entries.first(where: {
            $0.folder.url.standardizedFileURL == standardizedURL
        }) {
            return existing.folder
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw LibraryFoldersError.notAFolder(url)
        }

        let startedAccess = url.startAccessingSecurityScopedResource()
        let bookmark: (data: Data, isSecurityScoped: Bool)
        do {
            bookmark = try makeBookmark(for: url)
        } catch {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }

        let folder = LibraryFolder(url: url)
        let stored = StoredFolder(
            id: folder.id,
            bookmarkData: bookmark.data,
            isSecurityScoped: bookmark.isSecurityScoped,
            lastKnownPath: url.path,
        )
        entries.append(Entry(folder: folder, stored: stored))
        if startedAccess {
            accessedURLs[folder.id] = url
        }

        do {
            try saveStore()
        } catch {
            entries.removeLast()
            if let accessedURL = accessedURLs.removeValue(forKey: folder.id) {
                accessedURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }

        return folder
    }

    /// Forgets a folder without changing anything on disk inside it.
    public func remove(_ id: LibraryFolder.ID) {
        loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.folder.id == id }) else { return }

        entries.remove(at: index)
        if let url = accessedURLs.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
        try? saveStore()
    }

    /// Returns the folders currently held in memory, in the order they were added.
    public func folders() -> [LibraryFolder] {
        entries.map(\.folder)
    }

    private func loadIfNeeded() {
        if !didLoad {
            _ = load()
        }
    }

    private func resolve(_ stored: StoredFolder, refreshedStore: inout Bool) -> Entry {
        var isStale = false
        let options: URL.BookmarkResolutionOptions = stored.isSecurityScoped ? [.withSecurityScope] : []

        guard let url = try? URL(
            resolvingBookmarkData: stored.bookmarkData,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        ) else {
            return Entry(
                folder: LibraryFolder(
                    id: stored.id,
                    url: URL(fileURLWithPath: stored.lastKnownPath, isDirectory: true),
                    isAvailable: false,
                ),
                stored: stored,
            )
        }

        if url.startAccessingSecurityScopedResource() {
            accessedURLs[stored.id] = url
        }

        var isDirectory: ObjCBool = false
        let isAvailable = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue

        var refreshed = stored
        refreshed.lastKnownPath = url.path
        if isStale, let bookmark = try? makeBookmark(for: url) {
            refreshed.bookmarkData = bookmark.data
            refreshed.isSecurityScoped = bookmark.isSecurityScoped
            refreshedStore = true
        }
        if refreshed.lastKnownPath != stored.lastKnownPath {
            refreshedStore = true
        }

        return Entry(
            folder: LibraryFolder(id: stored.id, url: url, isAvailable: isAvailable),
            stored: refreshed,
        )
    }

    private func makeBookmark(for url: URL) throws -> (data: Data, isSecurityScoped: Bool) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil,
            )
            return (data, true)
        } catch {
            // Tests run outside the sandbox, where plain bookmarks still remember reachable folders.
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            return (data, false)
        }
    }

    private func stopAccessingAllFolders() {
        for url in accessedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
    }

    private func createStoreDirectory() throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
    }

    private func saveStore() throws {
        try createStoreDirectory()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(entries.map(\.stored))
        try data.write(to: storeURL, options: .atomic)
    }
}

/// Why a folder could not be added to the library, in words the user reads.
public enum LibraryFoldersError: Error, LocalizedError {
    case notAFolder(URL)

    public var errorDescription: String? {
        switch self {
        case .notAFolder:
            String(localized: "Only folders can be added to the library, and this is not one.")
        }
    }
}
