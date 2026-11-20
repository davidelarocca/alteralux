import AlteraluxKit
import Foundation
import Observation

/// Which photos of a folder the grid shows.
enum LibraryFilter: Hashable, CaseIterable {
    case all
    /// Only the photos that have adjustments.
    case adjusted
}

/// A folder the user added, with what is in it.
struct LibraryRoot: Identifiable {
    let folder: LibraryFolder
    /// The folder and its subfolders, with the number of photos in each. `nil` when the folder
    /// cannot be reached (a disk not connected, a folder deleted).
    var tree: FolderNode?

    var id: LibraryFolder.ID {
        folder.id
    }
}

/// The library: the folders the user added, shown as they are on disk, the one on screen and its
/// photos. There is no catalogue: what is here is read from the folders, and read again when
/// they change.
@MainActor
@Observable
final class LibraryModel {
    private(set) var roots: [LibraryRoot] = []
    /// The folder whose photos the grid shows: one the user added, or one inside it.
    private(set) var selectedFolder: URL?
    /// The photos directly in `selectedFolder`, in the Finder's order.
    private(set) var photos: [URL] = []
    /// Those of `photos` that have adjustments.
    private(set) var adjusted: Set<URL> = []
    var filter = LibraryFilter.all {
        didSet { selection.formIntersection(visiblePhotos) }
    }

    /// The photos picked in the grid.
    var selection: Set<URL> = []
    /// Set while the folders are read at launch.
    private(set) var isLoading = false

    /// The thumbnails of the grid and of the strip.
    @ObservationIgnored let thumbnails: ThumbnailProvider
    @ObservationIgnored private let folders: LibraryFolders
    @ObservationIgnored private let hasAdjustments: @Sendable (URL) -> Bool
    @ObservationIgnored private var watchers: [LibraryFolder.ID: Task<Void, Never>] = [:]
    /// The photo a Shift-click or an arrow key starts from.
    @ObservationIgnored private var anchor: URL?
    /// Counts the folders shown, to drop what was read for one that is no longer on screen.
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - storeURL: the file where the added folders are remembered.
    ///   - cacheDirectory: where thumbnails are kept between launches; `nil` keeps none on disk.
    ///   - hasAdjustments: whether a photo has adjustments kept for it.
    init(storeURL: URL, cacheDirectory: URL?, hasAdjustments: @escaping @Sendable (URL) -> Bool) {
        folders = LibraryFolders(storeURL: storeURL)
        thumbnails = ThumbnailProvider(cacheDirectory: cacheDirectory)
        self.hasAdjustments = hasAdjustments
    }

    /// Whether the user has added any folder.
    var isEmpty: Bool {
        roots.isEmpty
    }

    /// The photos the grid shows: those of the folder that pass the filter.
    var visiblePhotos: [URL] {
        switch filter {
        case .all: photos
        case .adjusted: photos.filter(adjusted.contains)
        }
    }

    /// The folder on screen as the tree has it, with its name and count.
    var selectedNode: FolderNode? {
        guard let selectedFolder else { return nil }
        return roots.lazy.compactMap { $0.tree.flatMap { Self.node(at: selectedFolder, in: $0) } }.first
    }

    // MARK: - Folders

    /// Reads the folders remembered from earlier launches, and shows the first.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        let remembered = await folders.load()
        var read: [LibraryRoot] = []
        for folder in remembered {
            await read.append(Self.root(for: folder))
        }
        roots = read
        for root in roots {
            watch(root.folder)
        }
        if selectedFolder == nil, let first = roots.first(where: { $0.tree != nil }) {
            await select(first.folder.url)
        }
    }

    /// Adds a folder the user chose, and shows it. A folder already added is only shown.
    func add(_ url: URL) async throws {
        let folder = try await folders.add(url)
        if !roots.contains(where: { $0.id == folder.id }) {
            await roots.append(Self.root(for: folder))
            watch(folder)
        }
        await select(folder.url)
    }

    /// Forgets a folder the user added. Nothing on disk changes.
    func remove(_ id: LibraryRoot.ID) async {
        guard let index = roots.firstIndex(where: { $0.id == id }) else { return }
        let removed = roots.remove(at: index)
        watchers.removeValue(forKey: id)?.cancel()
        await folders.remove(id)
        // The folder on screen went with it: show another, or nothing.
        let wasOnScreen = selectedFolder.map { shown in
            removed.folder.url == shown || removed.tree.flatMap { Self.node(at: shown, in: $0) } != nil
        } ?? false
        guard wasOnScreen else { return }
        if let next = roots.first(where: { $0.tree != nil }) {
            await select(next.folder.url)
        } else {
            generation += 1
            show(nil, photos: [], adjusted: [])
        }
    }

    /// Shows the photos of `folder`: one the user added, or one inside it.
    func select(_ folder: URL) async {
        generation += 1
        let current = generation
        selectedFolder = folder
        selection = []
        let (found, marked) = await contents(of: folder)
        guard current == generation else { return }
        show(folder, photos: found, adjusted: marked)
    }

    /// Reads the folders again: something changed on disk, or the app changed it.
    func refresh() async {
        for index in roots.indices {
            roots[index] = await Self.root(for: roots[index].folder)
        }
        guard let folder = selectedFolder else { return }
        let current = generation
        let (found, marked) = await contents(of: folder)
        guard current == generation else { return }
        show(folder, photos: found, adjusted: marked)
    }

    /// Notes that a photo now has adjustments, or no longer: the mark in the grid follows without
    /// reading the folder again.
    func noteAdjustments(of photo: URL) {
        // The same file can come with two addresses (through a link in its path): compare the
        // files, and keep the address the folder gave.
        let file = photo.standardizedFileURL
        guard let listed = photos.first(where: { $0.standardizedFileURL == file }) else { return }
        if hasAdjustments(listed) {
            adjusted.insert(listed)
        } else {
            adjusted.remove(listed)
        }
    }

    // MARK: - Selection

    /// A click on a photo of the grid: it becomes the selection; with Command it joins or leaves
    /// it; with Shift everything from the last photo clicked to this one joins it.
    func click(_ photo: URL, toggling: Bool = false, extending: Bool = false) {
        let shown = visiblePhotos
        if extending, let anchor, let first = shown.firstIndex(of: anchor), let last = shown.firstIndex(of: photo) {
            selection.formUnion(shown[min(first, last) ... max(first, last)])
        } else if toggling {
            selection.formSymmetricDifference([photo])
            anchor = photo
        } else {
            selection = [photo]
            anchor = photo
        }
    }

    /// Moves a single selection to the photo before or after it, for the arrow keys.
    func moveSelection(by offset: Int) {
        let shown = visiblePhotos
        guard !shown.isEmpty else { return }
        let current = anchor.flatMap(shown.firstIndex) ?? (offset > 0 ? -1 : shown.count)
        let target = shown[min(max(current + offset, 0), shown.count - 1)]
        selection = [target]
        anchor = target
    }

    func selectAll() {
        selection = Set(visiblePhotos)
    }

    func clearSelection() {
        selection = []
    }

    /// The photo the keyboard acts on: the last one clicked or moved to, when it is selected.
    var focusedPhoto: URL? {
        anchor.flatMap { selection.contains($0) ? $0 : nil } ?? visiblePhotos.first(where: selection.contains)
    }

    // MARK: - Reading

    private func show(_ folder: URL?, photos found: [URL], adjusted marked: Set<URL>) {
        selectedFolder = folder
        photos = found
        adjusted = marked
        selection.formIntersection(visiblePhotos)
    }

    /// The photos of a folder and which of them have adjustments, read off the main actor.
    private func contents(of folder: URL) async -> ([URL], Set<URL>) {
        let hasAdjustments = hasAdjustments
        return await Task.detached(priority: .userInitiated) {
            let found = (try? FolderContents.photos(in: folder)) ?? []
            return (found, Set(found.filter(hasAdjustments)))
        }.value
    }

    private static func root(for folder: LibraryFolder) async -> LibraryRoot {
        guard folder.isAvailable else { return LibraryRoot(folder: folder, tree: nil) }
        let tree = await Task.detached(priority: .userInitiated) {
            try? FolderContents.tree(of: folder.url)
        }.value
        return LibraryRoot(folder: folder, tree: tree)
    }

    private static func node(at url: URL, in tree: FolderNode) -> FolderNode? {
        if tree.url.standardizedFileURL == url.standardizedFileURL {
            return tree
        }
        return tree.children.lazy.compactMap { node(at: url, in: $0) }.first
    }

    /// Follows the changes on disk inside a folder the user added.
    private func watch(_ folder: LibraryFolder) {
        guard folder.isAvailable, watchers[folder.id] == nil else { return }
        let watcher = FolderWatcher(url: folder.url)
        watchers[folder.id] = Task { [weak self] in
            for await _ in watcher.changes {
                await self?.refresh()
            }
        }
    }
}
