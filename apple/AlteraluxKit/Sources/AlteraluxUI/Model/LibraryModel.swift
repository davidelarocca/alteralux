import AlteraluxKit
import Foundation
import Observation

/// Which photos of a folder the grid shows.
enum LibraryFilter: Hashable, CaseIterable {
    case all
    /// Only the photos that have adjustments.
    case adjusted
    /// Only the photos the user discarded, which the other two hide.
    case discarded
}

/// What the photos of a folder are sorted by.
enum LibrarySort: Hashable, CaseIterable {
    /// By name, as the Finder orders them.
    case name
    /// By the date the file was created.
    case date
    /// By kind of file, and by name within a kind.
    case kind
}

/// Which kinds of file the grid shows.
enum LibraryKinds: Hashable, CaseIterable {
    case all
    /// Camera RAW files only.
    case raw
    /// Everything but camera RAW files: JPEG, HEIC, TIFF and the like.
    case other
}

/// What was read of a folder: its photos, which carry adjustments and the discarded mark, and
/// what each says about itself.
private struct FolderListing: Sendable {
    var photos: [URL] = []
    var adjusted: Set<URL> = []
    var discarded: Set<URL> = []
    var infos: [URL: PhotoInfo] = [:]
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
    /// Those of `photos` the user discarded: marked, hidden, and still on disk.
    private(set) var discarded: Set<URL> = []
    /// The shape, date, kind, size and tags of each of `photos`, read with the folder.
    private(set) var infos: [URL: PhotoInfo] = [:]
    var filter = LibraryFilter.all {
        didSet { selection.formIntersection(visiblePhotos) }
    }

    /// What the photos are sorted by, and whether from the first to the last.
    var sort = LibrarySort.name
    var sortsAscending = true
    /// The kinds of file shown.
    var kinds = LibraryKinds.all {
        didSet { selection.formIntersection(visiblePhotos) }
    }

    /// The Finder tag a photo must carry to be shown; `nil` shows the photos whatever their tags.
    var tagFilter: String? {
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
    @ObservationIgnored private let discards: DiscardStore
    @ObservationIgnored private var watchers: [LibraryFolder.ID: Task<Void, Never>] = [:]
    /// The photo a Shift-click or an arrow key starts from.
    @ObservationIgnored private var anchor: URL?
    /// Counts the folders shown, to drop what was read for one that is no longer on screen.
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - storeURL: the file where the added folders are remembered.
    ///   - cacheDirectory: where thumbnails are kept between launches; `nil` keeps none on disk.
    ///   - hasAdjustments: whether a photo has adjustments kept for it.
    ///   - discards: where the discarded mark of a photo is kept.
    init(
        storeURL: URL, cacheDirectory: URL?, discards: DiscardStore,
        hasAdjustments: @escaping @Sendable (URL) -> Bool,
    ) {
        folders = LibraryFolders(storeURL: storeURL)
        thumbnails = ThumbnailProvider(cacheDirectory: cacheDirectory)
        self.discards = discards
        self.hasAdjustments = hasAdjustments
    }

    /// Whether the user has added any folder.
    var isEmpty: Bool {
        roots.isEmpty
    }

    /// The photos the grid shows: those of the folder that pass the filters, in the order asked.
    var visiblePhotos: [URL] {
        let shown = filteredPhotos.filter(passesKindAndTag)
        guard sort != .name || !sortsAscending else { return shown }
        // The folder's own order settles what the sort leaves equal.
        let place = Dictionary(uniqueKeysWithValues: shown.enumerated().map { ($1, $0) })
        let sorted = shown.sorted { lhs, rhs in
            switch sort {
            case .name:
                break
            case .date:
                let (first, second) = (infos[lhs]?.date ?? .distantFuture, infos[rhs]?.date ?? .distantFuture)
                if first != second {
                    return first < second
                }
            case .kind:
                let (first, second) = (lhs.pathExtension.lowercased(), rhs.pathExtension.lowercased())
                if first != second {
                    return first < second
                }
            }
            return (place[lhs] ?? 0) < (place[rhs] ?? 0)
        }
        return sortsAscending ? sorted : sorted.reversed()
    }

    /// The photos of the folder that pass the filter of the toolbar, before kind and tag.
    private var filteredPhotos: [URL] {
        switch filter {
        case .all: photos.filter { !discarded.contains($0) }
        case .adjusted: photos.filter { adjusted.contains($0) && !discarded.contains($0) }
        case .discarded: photos.filter(discarded.contains)
        }
    }

    private func passesKindAndTag(_ photo: URL) -> Bool {
        let info = infos[photo]
        switch kinds {
        case .all: break
        case .raw: if info?.isRaw != true {
                return false
            }
        case .other: if info?.isRaw == true {
                return false
            }
        }
        if let tagFilter {
            return info?.tags.contains { $0.name == tagFilter } ?? false
        }
        return true
    }

    /// Whether a kind or a tag is hiding photos of the folder.
    var hasFilters: Bool {
        kinds != .all || tagFilter != nil
    }

    /// Shows the photos of every kind again, whatever their tags.
    func clearFilters() {
        kinds = .all
        tagFilter = nil
    }

    /// How many photos the toolbar's filter lets through, before kind and tag: what "38 of 412"
    /// counts against.
    var filteredCount: Int {
        filteredPhotos.count
    }

    /// The Finder tags the photos of the folder carry, by name, each once.
    var tagsInFolder: [FinderTag] {
        var seen: [String: FinderTag] = [:]
        for photo in photos {
            for tag in infos[photo]?.tags ?? [] where seen[tag.name] == nil || seen[tag.name]?.color == nil {
                seen[tag.name] = tag
            }
        }
        return seen.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The size on disk of `chosen`, in bytes.
    func size(of chosen: some Sequence<URL>) -> Int64 {
        chosen.reduce(0) { $0 + (infos[$1]?.fileSize ?? 0) }
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
            show(nil, FolderListing())
        }
    }

    /// Shows the photos of `folder`: one the user added, or one inside it.
    func select(_ folder: URL) async {
        generation += 1
        let current = generation
        selectedFolder = folder
        selection = []
        let listing = await contents(of: folder)
        guard current == generation else { return }
        show(folder, listing)
    }

    /// Reads the folders again: something changed on disk, or the app changed it.
    func refresh() async {
        for index in roots.indices {
            roots[index] = await Self.root(for: roots[index].folder)
        }
        guard let folder = selectedFolder else { return }
        let current = generation
        let listing = await contents(of: folder)
        guard current == generation else { return }
        show(folder, listing)
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

    /// The photos a rectangle dragged over the grid covers become the selection, as in the
    /// Finder: with Shift they join the photos selected before, with Command they join or
    /// leave it.
    func select(covered: Set<URL>, before: Set<URL> = [], toggling: Bool = false) {
        let covered = covered.intersection(visiblePhotos)
        selection = toggling ? before.symmetricDifference(covered) : before.union(covered)
        if let first = visiblePhotos.first(where: covered.contains) {
            anchor = first
        }
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

    // MARK: - Actions on photos

    /// Every folder of the library, in the order of the list: the places photos can be moved or
    /// copied to. The sandbox lets the app write only into folders the user added.
    var destinations: [FolderNode] {
        func flattened(_ node: FolderNode) -> [FolderNode] {
            [node] + node.children.flatMap(flattened)
        }
        return roots.compactMap(\.tree).flatMap(flattened)
    }

    /// Marks photos as discarded, or takes the mark away. They stay on disk; the library hides
    /// the discarded ones except under their own filter. Returns the photos whose mark changed.
    @discardableResult
    func setDiscarded(_ isDiscarded: Bool, for chosen: [URL]) -> [URL] {
        var changed: [URL] = []
        for photo in chosen where discarded.contains(photo) != isDiscarded {
            guard (try? discards.setDiscarded(isDiscarded, for: photo)) != nil else { continue }
            if isDiscarded {
                discarded.insert(photo)
            } else {
                discarded.remove(photo)
            }
            changed.append(photo)
        }
        selection.formIntersection(visiblePhotos)
        return changed
    }

    /// Moves the discarded photos of the folder on screen to the Trash, and returns what
    /// happened to each.
    func emptyDiscarded() async -> [FileActionResult] {
        let files = photos.filter(discarded.contains)
        let results = await Task.detached(priority: .userInitiated) { PhotoFileActions.trash(files) }.value
        await refresh()
        return results
    }

    /// Moves photos into a folder of the library.
    func move(_ files: [URL], to folder: URL) async -> [FileActionResult] {
        let results = await Task.detached(priority: .userInitiated) { PhotoFileActions.move(files, to: folder) }.value
        await refresh()
        return results
    }

    /// Copies photos into a folder of the library.
    func copy(_ files: [URL], to folder: URL) async -> [FileActionResult] {
        let results = await Task.detached(priority: .userInitiated) { PhotoFileActions.copy(files, to: folder) }.value
        await refresh()
        return results
    }

    /// The Finder tags of the selected photos, each with the number of them that carry it.
    func tagsOfSelection() -> [String: Int] {
        PhotoFileActions.tags(ofAll: Array(selection))
    }

    /// Puts a Finder tag on photos, or takes it off.
    @discardableResult
    func setTag(_ tag: FinderTag, isOn: Bool, for files: [URL]) -> [FileActionResult] {
        let results = isOn ? PhotoFileActions.addTag(tag, to: files) : PhotoFileActions.removeTag(tag.name, from: files)
        // The dots of the grid and the tags to filter by follow at once.
        Task {
            let read = await Task.detached(priority: .userInitiated) { PhotoInfoReader.infos(of: files) }.value
            for (photo, info) in read where infos[photo] != nil {
                infos[photo] = info
            }
            selection.formIntersection(visiblePhotos)
        }
        return results
    }

    // MARK: - Reading

    private func show(_ folder: URL?, _ listing: FolderListing) {
        selectedFolder = folder
        photos = listing.photos
        adjusted = listing.adjusted
        discarded = listing.discarded
        infos = listing.infos
        // A tag no photo of this folder carries would hide them all.
        if let tagFilter, !tagsInFolder.contains(where: { $0.name == tagFilter }) {
            self.tagFilter = nil
        }
        selection.formIntersection(visiblePhotos)
    }

    /// The photos of a folder with their marks, read off the main actor.
    private func contents(of folder: URL) async -> FolderListing {
        let (hasAdjustments, discards) = (hasAdjustments, discards)
        return await Task.detached(priority: .userInitiated) {
            let found = (try? FolderContents.photos(in: folder)) ?? []
            return FolderListing(
                photos: found, adjusted: Set(found.filter(hasAdjustments)),
                discarded: Set(found.filter(discards.isDiscarded)),
                infos: PhotoInfoReader.infos(of: found),
            )
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
