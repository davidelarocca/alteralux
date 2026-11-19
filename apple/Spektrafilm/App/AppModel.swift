import AppKit
import Observation
import SpektrafilmEngine
import SpektrafilmKit
import UniformTypeIdentifiers

/// One photo in the strip, with its own adjustments.
@MainActor
@Observable
final class PhotoItem: Identifiable {
    let id = UUID()
    let url: URL
    var settings: DevelopSettings
    var thumbnail: CGImage?
    /// Whether the app holds a security-scoped access on `url` to release.
    fileprivate let isScoped: Bool

    var name: String { url.lastPathComponent }

    fileprivate init(url: URL, settings: DevelopSettings, isScoped: Bool) {
        self.url = url
        self.settings = settings
        self.isScoped = isScoped
    }
}

/// How the photo is scaled in the viewer.
enum ZoomCommand: Equatable {
    case fit
    case actualSize
    case zoomIn
    case zoomOut
}

/// The state of the app: the film catalogue, the open photos, the settings of
/// the selected one and its latest developed preview.
@MainActor
@Observable
final class AppModel {
    // MARK: Catalogue

    private(set) var films: [StockInfo] = []
    private(set) var papers: [StockInfo] = []

    // MARK: Photos

    private(set) var photos: [PhotoItem] = []
    private(set) var selectedID: PhotoItem.ID?
    /// Adjustments of the selected photo (the inspector edits these).
    var settings = DevelopSettings()
    var exportOptions = ExportOptions()

    /// Decoded pixels of the selected photo.
    private(set) var loaded: LoadedImage?
    /// The selected photo as the system renders it, for the comparison.
    private(set) var original: CGImage?
    /// The selected photo developed with `settings`.
    private(set) var preview: DevelopedImage?

    // MARK: Viewer

    /// Show the undeveloped original instead of the developed photo.
    var showsOriginal = false
    /// The latest zoom request for the viewer; `zoomRequestID` changes on
    /// every request so repeating the same command works.
    private(set) var zoomCommand = ZoomCommand.fit
    private(set) var zoomRequestID = 0
    /// Viewer scale relative to the photo's actual pixels (1 = 100%).
    private(set) var viewerScale = 0.0

    // MARK: Activity

    private(set) var isStarting = true
    private(set) var isLoading = false
    private(set) var isRendering = false
    private(set) var isExporting = false

    // MARK: Presentation

    var isImporterPresented = false
    var isExportPresented = false
    var alertMessage: String?

    /// File types offered by the Open panel and accepted by drag and drop.
    static let openableTypes: [UTType] = [.rawImage, .image]

    /// Long side of the standard live preview, in pixels.
    private nonisolated static let standardPreviewDimension = 2048
    private nonisolated static let thumbnailDimension = 240

    /// Long side the viewer currently needs, in pixels (0 = full resolution).
    private var previewDimension = AppModel.standardPreviewDimension

    private var renderer: FilmRenderer?
    private var renderLoop: Task<Void, Never>?
    private var needsRender = false
    private var loadGeneration = 0

    var selection: PhotoItem? { photos.first { $0.id == selectedID } }
    var hasPhoto: Bool { selection != nil }
    var canExport: Bool { loaded != nil && !isExporting }

    var selectedFilm: StockInfo? { films.first { $0.id == settings.filmID } }
    var selectedPaper: StockInfo? { papers.first { $0.id == settings.paperID } }

    /// "Portra 400 → Portra Endura", shown under the window title.
    var materialsSummary: String {
        guard hasPhoto, let film = selectedFilm else { return "" }
        if settings.scanFilm { return film.displayName }
        guard let paper = selectedPaper else { return film.displayName }
        return "\(film.displayName) → \(paper.displayName)"
    }

    /// Backend and timing of the last preview render, for diagnostics.
    var renderSummary: String {
        guard let preview else { return "" }
        return "\(preview.stats.backend) · \(preview.width) × \(preview.height) · "
            + "\(Int(preview.stats.totalMs.rounded())) ms"
    }

    // MARK: - Startup

    /// Creates the engine. Called once when the window appears.
    func start() async {
        guard renderer == nil else { return }
        defer { isStarting = false }
        do {
            guard let data = Bundle.main.resourceURL?.appendingPathComponent("data"),
                FileManager.default.fileExists(atPath: data.path)
            else { throw SpektrafilmError.missingEngineData }
            let renderer = try await Task.detached(priority: .userInitiated) {
                try FilmRenderer(dataDirectory: data)
            }.value
            let stocks = try renderer.stocks()
            self.renderer = renderer
            films = stocks.filter { $0.kind == .film }
            papers = stocks.filter { $0.kind == .paper }
            requestRender()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: - Opening and selecting

    /// Adds photos to the strip and selects the first new one.
    func open(_ urls: [URL]) {
        var firstNew: PhotoItem?
        for url in urls {
            if let existing = photos.first(where: { $0.url == url }) {
                firstNew = firstNew ?? existing
                continue
            }
            let isScoped = url.startAccessingSecurityScopedResource()
            // A new photo starts from the look currently on screen.
            var initial = DevelopSettings()
            initial.filmID = settings.filmID
            initial.paperID = settings.paperID
            initial.scanFilm = settings.scanFilm
            let item = PhotoItem(url: url, settings: initial, isScoped: isScoped)
            photos.append(item)
            firstNew = firstNew ?? item
            loadThumbnail(for: item)
        }
        if let firstNew { select(firstNew) }
    }

    func select(_ item: PhotoItem) {
        guard item.id != selectedID else { return }
        selection?.settings = settings
        selectedID = item.id
        settings = item.settings
        showsOriginal = false
        // A newly selected photo starts fitted to the window.
        zoom(.fit)
        loadSelection()
    }

    /// Removes a photo from the strip (the file itself is untouched).
    func remove(_ item: PhotoItem) {
        guard let index = photos.firstIndex(where: { $0.id == item.id }) else { return }
        photos.remove(at: index)
        if item.isScoped { item.url.stopAccessingSecurityScopedResource() }
        guard item.id == selectedID else { return }
        selectedID = nil
        loaded = nil
        original = nil
        preview = nil
        if let next = photos.indices.contains(index) ? photos[index] : photos.last {
            select(next)
        }
    }

    func selectAdjacent(offset: Int) {
        guard let index = photos.firstIndex(where: { $0.id == selectedID }) else { return }
        let target = index + offset
        if photos.indices.contains(target) { select(photos[target]) }
    }

    private func loadSelection() {
        guard let item = selection else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let url = item.url
        loaded = nil
        original = nil
        preview = nil
        isLoading = true
        Task {
            do {
                async let decoded = Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(url)
                }.value
                async let system = Task.detached(priority: .userInitiated) {
                    SendableImage(
                        ImageLoader.originalPreview(
                            of: url, maxDimension: Self.standardPreviewDimension))
                }.value
                let (loadedImage, originalImage) = try await (decoded, system)
                // Ignore the result if another photo was selected meanwhile.
                guard generation == loadGeneration else { return }
                loaded = loadedImage
                original = originalImage.image
                isLoading = false
                requestRender()
            } catch {
                guard generation == loadGeneration else { return }
                isLoading = false
                alertMessage = error.localizedDescription
            }
        }
    }

    private func loadThumbnail(for item: PhotoItem) {
        let url = item.url
        Task {
            let image = await Task.detached(priority: .utility) {
                SendableImage(
                    ImageLoader.originalPreview(of: url, maxDimension: Self.thumbnailDimension))
            }.value
            if item.thumbnail == nil { item.thumbnail = image.image }
        }
    }

    // MARK: - Settings

    /// Called when the settings change: keeps the photo's copy in sync and
    /// refreshes the preview.
    func settingsDidChange() {
        selection?.settings = settings
        requestRender()
    }

    /// Chooses a film and applies what follows from it: slides are scanned
    /// directly, negatives are printed on the paper their profile recommends.
    func chooseFilm(_ id: String) {
        settings.filmID = id
        guard let film = selectedFilm else { return }
        settings.scanFilm = film.isPositive
        if let target = film.targetPrint, papers.contains(where: { $0.id == target }) {
            settings.paperID = target
        }
    }

    /// Restores the default adjustments, keeping the chosen film and paper.
    func resetAdjustments() {
        var fresh = DevelopSettings()
        fresh.filmID = settings.filmID
        fresh.paperID = settings.paperID
        fresh.scanFilm = settings.scanFilm
        settings = fresh
    }

    // MARK: - Viewer

    func zoom(_ command: ZoomCommand) {
        zoomCommand = command
        zoomRequestID += 1
    }

    /// Called by the viewer when its scale changes. Picks the preview
    /// resolution: the fast standard size while the whole photo is in view,
    /// full resolution once the user zooms in far enough to see the difference.
    func viewerDidChange(scale: Double) {
        viewerScale = scale
        guard let loaded else { return }
        let displayedLongSide = Double(max(loaded.width, loaded.height)) * scale
        let needsFullResolution =
            displayedLongSide > Double(Self.standardPreviewDimension) * 1.15
        let dimension = needsFullResolution ? 0 : Self.standardPreviewDimension
        if dimension != previewDimension {
            previewDimension = dimension
            requestRender()
        }
    }

    // MARK: - Rendering

    /// Renders the preview with the current settings. Calls made while a
    /// render is running collapse into one follow-up render with the latest
    /// settings, so dragging a slider never queues up stale frames.
    func requestRender() {
        guard loaded != nil, renderer != nil else { return }
        needsRender = true
        guard renderLoop == nil else { return }
        renderLoop = Task { await runRenderLoop() }
    }

    private func runRenderLoop() async {
        isRendering = true
        while needsRender, let loaded, let renderer {
            needsRender = false
            let generation = loadGeneration
            do {
                let developed = try await renderer.render(
                    loaded, settings: settings, quality: .preview(maxDimension: previewDimension))
                // Drop the frame if another photo was selected meanwhile.
                if generation == loadGeneration { preview = developed }
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        isRendering = false
        renderLoop = nil
        refreshSelectedThumbnail()
    }

    /// Updates the strip thumbnail with the developed look.
    private func refreshSelectedThumbnail() {
        guard let item = selection, let preview else { return }
        let image = SendableImage(preview.cgImage)
        Task {
            let thumbnail = await Task.detached(priority: .utility) {
                SendableImage(image.image.flatMap { Self.downscale($0, to: Self.thumbnailDimension) })
            }.value
            if let thumbnail = thumbnail.image { item.thumbnail = thumbnail }
        }
    }

    private nonisolated static func downscale(_ image: CGImage, to maxDimension: Int) -> CGImage? {
        let scale = Double(maxDimension) / Double(max(image.width, image.height))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Export

    func export() async {
        guard let loaded, let renderer, !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportOptions.format.contentType]
        panel.canCreateDirectories = true
        let baseName = loaded.url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue =
            "\(baseName) \(settings.filmID).\(exportOptions.format.fileExtension)"
        guard await panel.begin() == .OK, let destination = panel.url else { return }

        isExporting = true
        defer { isExporting = false }
        let options = exportOptions
        do {
            let developed = try await renderer.render(loaded, settings: settings, quality: .full)
            try await Task.detached(priority: .userInitiated) {
                try ImageExporter.write(
                    developed, to: destination, options: options, originalURL: loaded.url)
            }.value
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

/// Carries an immutable `CGImage` across tasks.
private struct SendableImage: @unchecked Sendable {
    let image: CGImage?
    init(_ image: CGImage?) { self.image = image }
}
