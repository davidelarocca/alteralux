import Foundation

/// The photos the user opened on their own, outside the library's folders, remembered between
/// launches with a bookmark each, in the order they were opened.
///
/// A photo opened from the Finder or dropped on the window can be read and written in the
/// sandbox until the app quits; its bookmark gives it back at the next launch. Its folder is
/// not given: the photo cannot be renamed, duplicated or moved from there.
public actor OpenedPhotos {
    private struct Stored: Codable {
        var bookmark: FolderBookmark
    }

    private let storeURL: URL
    private var stored: [Stored] = []
    private var photos: [URL] = []
    private var accessed: [URL] = []
    private var didLoad = false

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    deinit {
        for url in accessed {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// The photos remembered, found again where they are now; the ones that cannot be found are
    /// forgotten.
    public func load() -> [URL] {
        guard !didLoad else { return photos }
        didLoad = true
        guard let data = try? Data(contentsOf: storeURL),
              let read = try? PropertyListDecoder().decode([Stored].self, from: data)
        else { return [] }
        for entry in read {
            guard let url = entry.bookmark.resolve(), FileManager.default.fileExists(atPath: url.path) else { continue }
            if entry.bookmark.isSecurityScoped, url.startAccessingSecurityScopedResource() {
                accessed.append(url)
            }
            stored.append(entry)
            photos.append(url)
        }
        if stored.count != read.count {
            save()
        }
        return photos
    }

    /// Remembers photos the user just opened, after the ones already remembered; a photo
    /// remembered already keeps its place.
    public func add(_ urls: [URL]) -> [URL] {
        _ = load()
        let known = Set(photos.map(\.standardizedFileURL))
        var seen = Set<URL>()
        for url in urls {
            let file = url.standardizedFileURL
            guard !known.contains(file), seen.insert(file).inserted, let bookmark = try? FolderBookmark(for: url) else {
                continue
            }
            stored.append(Stored(bookmark: bookmark))
            photos.append(url)
        }
        save()
        return photos
    }

    /// Forgets photos. Nothing on disk changes.
    public func remove(_ urls: [URL]) -> [URL] {
        _ = load()
        let gone = Set(urls.map(\.standardizedFileURL))
        let kept = zip(stored, photos).filter { !gone.contains($0.1.standardizedFileURL) }
        stored = kept.map(\.0)
        photos = kept.map(\.1)
        save()
        return photos
    }

    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try? encoder.encode(stored).write(to: storeURL, options: .atomic)
    }
}
