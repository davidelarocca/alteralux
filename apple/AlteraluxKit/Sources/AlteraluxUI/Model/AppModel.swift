import AlteraluxEngine
import AlteraluxKit
import AppKit
import Observation
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

    var name: String {
        url.lastPathComponent
    }

    fileprivate init(url: URL, settings: DevelopSettings, isScoped: Bool) {
        self.url = url
        self.settings = settings
        self.isScoped = isScoped
    }
}

/// The state of the app: the film catalogue, the open photos, the settings of
/// the selected one and its latest developed preview.
@MainActor
@Observable
public final class AppModel {
    // MARK: Catalogue

    private(set) var films: [StockInfo] = []
    /// The films arranged for choosing one: grouped, searchable, each with its emblem.
    private(set) var filmCatalogue = FilmCatalogue()
    private(set) var papers: [StockInfo] = []

    // MARK: Photos

    private(set) var photos: [PhotoItem] = []
    private(set) var selectedID: PhotoItem.ID?
    /// Adjustments of the selected photo (the inspector edits these).
    var settings = DevelopSettings()
    var exportOptions = ExportOptions()

    /// The selected photo, open and decoded as the engine needs it.
    private(set) var sources: PhotoSources?
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
    /// How the viewer is showing the photo, as it last reported.
    private(set) var viewerZoom = ViewerZoom()

    /// The scales the zoom slider covers, relative to actual pixels: 5% to 800%.
    static let zoomScaleRange = 0.05 ... 8.0
    /// The zoom slider works on the base 2 logarithm of the scale, so each step multiplies the
    /// size by the same amount wherever the thumb is.
    static let zoomLevelRange = log2(zoomScaleRange.lowerBound) ... log2(zoomScaleRange.upperBound)
    static let zoomLevelStep = 0.1

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

    /// Long side of the lighter preview shown while the settings are changing.
    private nonisolated static let draftPreviewDimension = 1024
    private nonisolated static let thumbnailDimension = 240
    /// How long the settings must stay still before the preview is rendered at its full size.
    private nonisolated static let settleDelay = Duration.milliseconds(150)
    /// How long the standard preview stays, once the settings are still, before a preview that
    /// takes long replaces it. A render cannot be interrupted: one started at every short pause
    /// would keep the control waiting when the hand takes it up again.
    private nonisolated static let slowPreviewDelay = Duration.milliseconds(400)

    /// Long side of the photo as the viewer shows it, in display pixels (0 until it reports).
    private var displayedLongSide = 0.0

    private var renderer: FilmRenderer?
    private var renderLoop: Task<Void, Never>?
    private var needsRender = false
    private var loadGeneration = 0
    /// Set while the settings are changing: a slider is being dragged, a key is held down.
    private var isAdjusting = false
    private var settle: Task<Void, Never>?
    /// Set from a change of the settings until they have been still for a while: meanwhile the
    /// standard preview stands in for one that takes long.
    private var holdsSlowPreview = false
    private var slowPreviewRelease: Task<Void, Never>?
    /// Whether the preview on screen is smaller than the one the viewer needs.
    private var previewIsDraft = false

    /// Where the engine's `data` folder is. `nil` means the app bundle's resources.
    private let dataDirectory: URL?

    /// - Parameter dataDirectory: the engine's `data` folder; the app passes
    ///   nothing and ships it in its resources, tests pass the submodule's.
    public init(dataDirectory: URL? = nil) {
        self.dataDirectory = dataDirectory
    }

    var selection: PhotoItem? {
        photos.first { $0.id == selectedID }
    }

    var hasPhoto: Bool {
        selection != nil
    }

    var canExport: Bool {
        sources != nil && !isExporting
    }

    /// The zoom commands act on a photo that is loaded.
    var canZoom: Bool {
        sources != nil
    }

    /// The size of the selected photo, in pixels, once it is open.
    var photoSize: CGSize? {
        sources.map { CGSize(width: $0.decoder.width, height: $0.decoder.height) }
    }

    /// Previous and next need another photo to go to.
    var canStepThroughPhotos: Bool {
        photos.count > 1
    }

    /// Whether there is a photo `offset` places from the selected one in the strip.
    func canSelectAdjacent(offset: Int) -> Bool {
        guard let index = photos.firstIndex(where: { $0.id == selectedID }) else { return false }
        return photos.indices.contains(index + offset)
    }

    /// The selected film as the list shows it, with its kind and its speed.
    var selectedFilmEntry: FilmEntry? {
        filmCatalogue.entry(id: settings.filmID)
    }

    var selectedFilm: StockInfo? {
        films.first { $0.id == settings.filmID }
    }

    var selectedPaper: StockInfo? {
        papers.first { $0.id == settings.paperID }
    }

    /// "Portra 400 → Portra Endura", shown under the window title.
    var materialsSummary: String {
        guard hasPhoto, let film = selectedFilm else { return "" }
        if settings.scanFilm {
            return film.displayName
        }
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
            guard
                let data = dataDirectory ?? Bundle.main.resourceURL?.appendingPathComponent("data"),
                FileManager.default.fileExists(atPath: data.path)
            else { throw AlteraluxError.missingEngineData }
            let renderer = try await Task.detached(priority: .userInitiated) {
                try FilmRenderer(dataDirectory: data)
            }.value
            let stocks = try renderer.stocks()
            self.renderer = renderer
            films = stocks.filter { $0.kind == .film }
            filmCatalogue = FilmCatalogue(films: films)
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
        if let firstNew {
            select(firstNew)
        }
    }

    func select(_ item: PhotoItem) {
        guard item.id != selectedID else { return }
        selection?.settings = settings
        selectedID = item.id
        settings = item.settings
        showsOriginal = false
        // A newly selected photo starts fitted to the window: as large as the last one if that
        // was fitted too, and otherwise at a size the viewer has yet to report.
        if !viewerZoom.isFitted {
            displayedLongSide = 0
        }
        zoom(.fit)
        loadSelection()
    }

    /// Removes a photo from the strip (the file itself is untouched).
    func remove(_ item: PhotoItem) {
        guard let index = photos.firstIndex(where: { $0.id == item.id }) else { return }
        photos.remove(at: index)
        if item.isScoped {
            item.url.stopAccessingSecurityScopedResource()
        }
        guard item.id == selectedID else { return }
        selectedID = nil
        sources = nil
        original = nil
        preview = nil
        if let next = photos.indices.contains(index) ? photos[index] : photos.last {
            select(next)
        }
    }

    /// Removes the selected photo from the strip.
    func removeSelection() {
        if let selection {
            remove(selection)
        }
    }

    func selectAdjacent(offset: Int) {
        guard let index = photos.firstIndex(where: { $0.id == selectedID }) else { return }
        let target = index + offset
        if photos.indices.contains(target) {
            select(photos[target])
        }
    }

    private func loadSelection() {
        guard let item = selection else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let url = item.url
        sources = nil
        original = nil
        preview = nil
        isLoading = true
        // Whatever was held back belonged to the photo before.
        slowPreviewRelease?.cancel()
        slowPreviewRelease = nil
        holdsSlowPreview = false
        // The photo as the system renders it, for the comparison: the preview does not wait for it.
        Task {
            let system = await Task.detached(priority: .userInitiated) {
                SendableImage(ImageLoader.originalPreview(of: url, maxDimension: PreviewSize.standard))
            }.value
            if generation == loadGeneration {
                original = system.image
            }
        }
        Task {
            do {
                // Opening reads what the file says about itself; its pixels are decoded for
                // each preview, at the size of that preview.
                let decoder = try await Task.detached(priority: .userInitiated) {
                    try PhotoDecoder(url: url)
                }.value
                // Ignore the result if another photo was selected meanwhile.
                guard generation == loadGeneration else { return }
                sources = PhotoSources(decoder: decoder)
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
                    ImageLoader.originalPreview(of: url, maxDimension: Self.thumbnailDimension),
                )
            }.value
            if item.thumbnail == nil {
                item.thumbnail = image.image
            }
        }
    }

    // MARK: - Settings

    /// Called when the settings change: keeps the photo's copy in sync and
    /// refreshes the preview.
    ///
    /// While a control moves the preview is rendered smaller, so it keeps up with the hand; the
    /// preview the viewer needs follows as soon as the settings stay still.
    func settingsDidChange() {
        selection?.settings = settings
        guard let sources, renderer != nil else { return }
        sources.settingsDidChange(settings)
        isAdjusting = true
        holdsSlowPreview = true
        slowPreviewRelease?.cancel()
        slowPreviewRelease = nil
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            isAdjusting = false
            requestRender()
        }
        requestRender()
    }

    /// Lets a preview that takes long through, once the settled one has been on screen for a
    /// while without the settings changing again.
    private func releaseSlowPreviewLater() {
        guard slowPreviewRelease == nil else { return }
        slowPreviewRelease = Task { [weak self] in
            try? await Task.sleep(for: Self.slowPreviewDelay)
            guard !Task.isCancelled, let self else { return }
            slowPreviewRelease = nil
            holdsSlowPreview = false
            if previewIsDraft {
                requestRender()
            }
        }
    }

    /// Chooses a film and applies what follows from it: slides are scanned
    /// directly, negatives are printed on the paper their profile recommends,
    /// and black and white negatives on a black and white print stock.
    func chooseFilm(_ id: String) {
        settings.filmID = id
        guard let film = selectedFilm else { return }
        settings.scanFilm = film.isPositive
        if let target = film.targetPrint, papers.contains(where: { $0.id == target }) {
            settings.paperID = target
            return
        }
        // The black and white profiles recommend no paper, and on a color paper they print
        // orange: a neutral gray comes out as a strong orange. Pair them with a black and white
        // print stock.
        let blackAndWhitePaper = papers.first(where: \.isBlackAndWhite)
        if film.isBlackAndWhite, selectedPaper?.isBlackAndWhite != true, let blackAndWhitePaper {
            settings.paperID = blackAndWhitePaper.id
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

    /// Called by the viewer when its scale changes. The preview follows the size of the photo
    /// on screen: see `PreviewSize`.
    func viewerDidChange(_ zoom: ViewerZoom) {
        viewerZoom = zoom
        guard let sources else { return }
        let current = previewDimension(photoLongSide: sources.longSide)
        displayedLongSide = Double(sources.longSide) * zoom.scale
        if previewDimension(photoLongSide: sources.longSide) != current {
            requestRender()
        }
    }

    /// Long side of the preview the viewer needs of the photo, in pixels (0 = full resolution).
    private func previewDimension(photoLongSide: Int) -> Int {
        PreviewSize.dimension(displayedLongSide: displayedLongSide, photoLongSide: photoLongSide)
    }

    // MARK: - Rendering

    /// Renders the preview with the current settings. Calls made while a
    /// render is running collapse into one follow-up render with the latest
    /// settings, so dragging a slider never queues up stale frames.
    func requestRender() {
        guard sources != nil, renderer != nil else { return }
        needsRender = true
        guard renderLoop == nil else { return }
        renderLoop = Task { await runRenderLoop() }
    }

    private func runRenderLoop() async {
        isRendering = true
        while needsRender, let sources, let renderer {
            needsRender = false
            let generation = loadGeneration
            let isSettled = !isAdjusting
            let settings = settings
            let dimension = nextRenderDimension(photoLongSide: sources.longSide)
            let isDraft = dimension != previewDimension(photoLongSide: sources.longSide)
            do {
                // The photo is decoded at the size of the preview: the engine scales nothing.
                let source = try await sources.source(dimension: dimension, settings: settings)
                let developed = try await renderer.render(
                    source, settings: settings, quality: .preview(maxDimension: 0),
                )
                // Drop the frame if another photo was selected meanwhile.
                if generation == loadGeneration {
                    preview = developed
                    previewIsDraft = isDraft
                    if isSettled, holdsSlowPreview {
                        releaseSlowPreviewLater()
                    }
                }
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        isRendering = false
        renderLoop = nil
        // The strip follows once the settings settle, not on every frame of a drag.
        if !previewIsDraft {
            refreshSelectedThumbnail()
            sources?.prepare(lighterDimension: Self.draftPreviewDimension, settings: settings)
        }
    }

    /// The long side of the next render (0 = full resolution): the lighter preview while the
    /// settings change, then what the viewer needs, with the standard preview standing in for
    /// one that takes long until the settings have been still for a while.
    private func nextRenderDimension(photoLongSide: Int) -> Int {
        if isAdjusting {
            return Self.draftPreviewDimension
        }
        let dimension = previewDimension(photoLongSide: photoLongSide)
        if holdsSlowPreview, PreviewSize.comesAfterStandard(dimension, photoLongSide: photoLongSide) {
            return PreviewSize.standard
        }
        return dimension
    }

    /// Updates the strip thumbnail with the developed look.
    private func refreshSelectedThumbnail() {
        guard let item = selection, let preview else { return }
        let image = SendableImage(preview.cgImage)
        Task {
            let thumbnail = await Task.detached(priority: .utility) {
                SendableImage(image.image.flatMap { Self.downscale($0, to: Self.thumbnailDimension) })
            }.value
            if let thumbnail = thumbnail.image {
                item.thumbnail = thumbnail
            }
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
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Export

    /// The name proposed for an exported file: the photo's name, the film as the user reads it,
    /// and the format's extension ("IMG_0042 Kodak Portra 400.jpg").
    nonisolated static func exportFileName(
        source: URL, film: String, format: ExportOptions.Format,
    ) -> String {
        let baseName = source.deletingPathExtension().lastPathComponent
        // A film's name must not read as a path in the save panel.
        let filmName = film.replacing("/", with: "-").replacing(":", with: "-")
        return "\(baseName) \(filmName).\(format.fileExtension)"
    }

    /// Asks where to save the developed photo, and writes it there.
    func export() async {
        guard let sources, !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportOptions.format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.exportFileName(
            source: sources.decoder.url,
            film: selectedFilm?.displayName ?? settings.filmID,
            format: exportOptions.format,
        )
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        await export(to: destination)
    }

    /// Develops the whole photo with the settings on screen and writes it to `destination`.
    func export(to destination: URL) async {
        guard let sources, let renderer, !isExporting else { return }
        let url = sources.decoder.url
        let settings = settings
        isExporting = true
        defer { isExporting = false }
        let options = exportOptions
        do {
            let whole = try await sources.source(dimension: 0, settings: settings)
            let developed = try await renderer.render(whole, settings: settings, quality: .full)
            try await Task.detached(priority: .userInitiated) {
                try ImageExporter.write(
                    developed, to: destination, options: options, originalURL: url,
                )
            }.value
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

/// Carries an immutable `CGImage` across tasks.
private struct SendableImage: @unchecked Sendable { // concurrency: CGImage is immutable once created
    let image: CGImage?
    init(_ image: CGImage?) {
        self.image = image
    }
}
