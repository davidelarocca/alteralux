import AlteraluxEngine
import AlteraluxKit
import AppKit
import Observation
import UniformTypeIdentifiers

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
    /// The automatic white balance of the selected photo, once it was measured.
    var automaticWhiteBalance: WhiteBalance?
    /// The selected photo as the system renders it, for the comparison.
    private(set) var original: CGImage?
    /// The selected photo developed with `settings`.
    private(set) var preview: DevelopedImage?
    /// The frame `preview` was developed with: `nil` for the whole photo.
    private(set) var previewCrop: PhotoCrop?
    /// The frame being chosen, while the crop controls are on screen.
    var cropSession: CropSession?

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
    var isExporting = false
    /// How far the export of several photos is, while one runs.
    var batchExport: BatchExportProgress?
    /// The export of several photos that is running, to stop it.
    var exportTask: Task<[FileActionResult], Never>?

    // MARK: Presentation

    var isImporterPresented = false
    /// The panel for adding a folder to the library.
    var isFolderImporterPresented = false

    var isExportPresented = false
    /// The photos the export sheet is for: the selected photos of the library, or none for the
    /// photo on screen.
    var photosToExport: [URL] = []
    /// Whether several photos go to a folder beside each original, or to one folder to choose.
    var exportsBesideOriginals = true
    /// Whether the export sheet develops the photos with a workflow, and not with their own
    /// adjustments and the options it shows.
    var exportsWithWorkflow = false
    /// The workflow chosen in the export sheet, kept for the next time.
    var exportWorkflow: Workflow.ID?
    /// An export that found files of an earlier one, and waits to be told what to do with them.
    var exportWaiting: WaitingExport?
    /// Takes away an exported file that a new export replaces. `nil` moves it to the Trash;
    /// tests remove it instead, to leave nothing in the Trash of whoever runs them.
    var discardExport: (@Sendable (URL) throws -> Void)?
    var alertMessage: String?

    /// File types offered by the Open panel and accepted by drag and drop.
    static let openableTypes: [UTType] = [.rawImage, .image]

    /// Long side of the lighter preview shown while the settings are changing.
    private nonisolated static let draftPreviewDimension = 1024
    nonisolated static let thumbnailDimension = 240
    /// The most the thumbnails kept on disk take, in bytes: thousands of photos' worth.
    private nonisolated static let thumbnailCacheLimit: Int64 = 512 * 1024 * 1024
    /// How long the settings must stay still before the preview is rendered at its full size.
    var settleDelay = Duration.milliseconds(150)
    /// How long the standard preview stays, once the settings are still, before a preview that
    /// takes long replaces it. A render cannot be interrupted: one started at every short pause
    /// would keep the control waiting when the hand takes it up again.
    var slowPreviewDelay = Duration.milliseconds(400)

    /// Long side of the photo as the viewer shows it, in display pixels (0 until it reports).
    private var displayedLongSide = 0.0

    private(set) var renderer: FilmRenderer?
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
    /// Where the lens profiles are: in the app, lensfun's database among its resources.
    private let lensesDirectory: URL?
    /// The lens profiles, once read: they correct the RAWs whose lens Apple's decoder does not know.
    private(set) var lenses: LensDatabase?
    /// Keeps the adjustments of each photo and the steps to undo.
    let history: EditHistory
    /// The folders the user added and the photos in them.
    let library: LibraryModel
    /// Whether the window shows the library instead of the photo being developed.
    var showsLibrary = false
    /// The recipes, by name, and where they are kept.
    var recipes: [Recipe] = []
    let recipeStore: RecipeStore
    /// The workflows, by name, and where they are kept.
    var workflows: [Workflow] = []
    let workflowStore: WorkflowStore
    /// The adjustments copied from a photo, to paste on others.
    var copiedAdjustments: DevelopSettings?
    /// The settings the last call of `settingsDidChange` has seen.
    private var seenSettings = DevelopSettings()

    /// - Parameters:
    ///   - dataDirectory: the engine's `data` folder; the app passes nothing and ships it in
    ///     its resources, tests pass the submodule's.
    ///   - editsDirectory: where the adjustments of photos that cannot be written are kept. The
    ///     app passes nothing and keeps them in its Application Support folder; anything else
    ///     that passes nothing (a test, a preview) gets a temporary folder, never the user's.
    ///   - lensesDirectory: the lens profiles' folder; the app passes nothing and ships lensfun's
    ///     database in its resources, anything else that passes nothing has none.
    public init(dataDirectory: URL? = nil, editsDirectory: URL? = nil, lensesDirectory: URL? = nil) {
        self.dataDirectory = dataDirectory
        self.lensesDirectory = lensesDirectory ?? (
            dataDirectory == nil && editsDirectory == nil
                ? Bundle.main.resourceURL?.appending(path: "lensfun/db") : nil
        )
        let edits = editsDirectory ?? (
            dataDirectory == nil
                ? URL.applicationSupportDirectory.appending(path: "Edits")
                : URL.temporaryDirectory.appending(path: "alteralux-edits-\(ProcessInfo.processInfo.processIdentifier)")
        )
        let store = EditStore(fallbackDirectory: edits)
        history = EditHistory(store: store)
        // The library's own files: in the app's folders, or beside the edits for anything else.
        let isApp = dataDirectory == nil && editsDirectory == nil
        let beside = URL(fileURLWithPath: edits.path + "-library", isDirectory: true)
        library = LibraryModel(
            storeURL: isApp
                ? URL.applicationSupportDirectory.appending(path: "Library/folders.plist")
                : beside.appending(path: "folders.plist"),
            cacheDirectory: isApp ? URL.cachesDirectory.appending(path: "Thumbnails") : beside.appending(path: "thumbnails"),
            discards: DiscardStore(fallbackDirectory: edits.appending(path: "Discarded")),
            preferences: isApp ? .standard : nil,
            hasAdjustments: { store.hasAdjustments(for: $0) },
            crop: { store.load(for: $0)?.crop },
        )
        recipeStore = RecipeStore(
            directory: isApp ? URL.applicationSupportDirectory.appending(path: "Recipes") : beside.appending(path: "recipes"),
        )
        workflowStore = WorkflowStore(
            directory: isApp ? URL.applicationSupportDirectory.appending(path: "Workflows") : beside.appending(path: "workflows"),
        )
        history.restore = { [weak self] item, settings in self?.restore(settings, to: item) }
        history.report = { [weak self] error in self?.alertMessage = error.localizedDescription }
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
            // The lens profiles are read meanwhile: a fraction of a second.
            let lenses = Task.detached(priority: .userInitiated) { [lensesDirectory] in
                lensesDirectory.flatMap { try? LensDatabase(directory: $0) }
            }
            let renderer = try await Task.detached(priority: .userInitiated) {
                try FilmRenderer(dataDirectory: data)
            }.value
            self.lenses = await lenses.value
            let stocks = try renderer.stocks()
            self.renderer = renderer
            films = stocks.filter { $0.kind == .film }
            filmCatalogue = FilmCatalogue(films: films)
            papers = stocks.filter { $0.kind == .paper }
            requestRender()
        } catch {
            alertMessage = error.localizedDescription
        }
        await loadRecipes()
        await loadWorkflows()
        // The library is where the app opens, unless it was started on a photo.
        await library.load()
        Task.detached(priority: .background) { [thumbnails = library.thumbnails] in
            thumbnails.pruneDiskCache(toAtMost: Self.thumbnailCacheLimit)
        }
        if photos.isEmpty, !library.isEmpty {
            showsLibrary = true
        }
    }

    // MARK: - Opening and selecting

    /// Adds photos to the strip and selects the first new one.
    func open(_ urls: [URL]) {
        if let first = add(urls) {
            select(first)
            showsLibrary = false
        }
    }

    /// Adds photos to the strip, and returns the first of them: new, or already there.
    private func add(_ urls: [URL]) -> PhotoItem? {
        var first: PhotoItem?
        for url in urls {
            if let existing = photos.first(where: { $0.url == url }) {
                first = first ?? existing
                continue
            }
            let isScoped = url.startAccessingSecurityScopedResource()
            // A photo comes back as it was left; a new one starts from the look on screen.
            var initial = DevelopSettings()
            initial.filmID = settings.filmID
            initial.paperID = settings.paperID
            initial.scanFilm = settings.scanFilm
            let item = PhotoItem(url: url, settings: history.kept(for: url) ?? initial, isScoped: isScoped)
            photos.append(item)
            first = first ?? item
            loadThumbnail(for: item)
        }
        return first
    }

    /// Puts the photos of a folder in the strip, in their order, and selects one: the photos
    /// that were there and are not among them leave it.
    func develop(_ photo: URL, among folderPhotos: [URL]) {
        let wanted = Set(folderPhotos)
        for item in photos where !wanted.contains(item.url) {
            remove(item)
        }
        _ = add(folderPhotos)
        let placed = Dictionary(uniqueKeysWithValues: folderPhotos.enumerated().map { ($1, $0) })
        photos.sort { (placed[$0.url] ?? .max) < (placed[$1.url] ?? .max) }
        if let item = photos.first(where: { $0.url == photo }) {
            select(item)
        }
        showsLibrary = false
    }

    func select(_ item: PhotoItem) {
        guard item.id != selectedID else { return }
        if let selection {
            // What was being changed on the photo before is kept now.
            selection.settings = settings
            history.settle(selection)
            settle?.cancel()
            settle = nil
            isAdjusting = false
        }
        selectedID = item.id
        // A frame being chosen belonged to the photo before.
        cropSession = nil
        settings = item.settings
        seenSettings = settings
        history.follow(item)
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
        if item.id == selectedID {
            item.settings = settings
        }
        history.settle(item)
        history.forget(item)
        photos.remove(at: index)
        if item.isScoped {
            // The adjustments are written while the photo can still be reached.
            Task { [history] in
                await history.waitUntilSaved()
                item.url.stopAccessingSecurityScopedResource()
            }
        }
        guard item.id == selectedID else { return }
        selectedID = nil
        // A photo still being opened must not come back once it has left the strip.
        loadGeneration += 1
        sources = nil
        automaticWhiteBalance = nil
        original = nil
        preview = nil
        if let next = photos.indices.contains(index) ? photos[index] : photos.last {
            select(next)
        }
    }

    private func loadSelection() {
        guard let item = selection else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let url = item.url
        sources = nil
        automaticWhiteBalance = nil
        original = nil
        preview = nil
        previewCrop = nil
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
                let decoder = try await Task.detached(priority: .userInitiated) { [lenses] in
                    try PhotoDecoder(url: url, lenses: lenses)
                }.value
                // Ignore the result if another photo was selected meanwhile.
                guard generation == loadGeneration else { return }
                sources = PhotoSources(decoder: decoder)
                isLoading = false
                requestRender()
                measureAutomaticWhiteBalance()
            } catch {
                guard generation == loadGeneration else { return }
                isLoading = false
                alertMessage = error.localizedDescription
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
        // Called once per change, whoever calls: the screen when it sees one, and the model
        // when it makes one itself.
        guard settings != seenSettings else { return }
        seenSettings = settings
        guard let item = selection else { return }
        item.settings = settings
        history.change(of: item)
        sources?.settingsDidChange(settings)
        measureAutomaticWhiteBalance()
        isAdjusting = true
        holdsSlowPreview = true
        slowPreviewRelease?.cancel()
        slowPreviewRelease = nil
        settle?.cancel()
        settle = Task { [weak self] in
            guard let delay = self?.settleDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.settleChange()
        }
        requestRender()
    }

    /// Ends the change in progress, as the settings standing still for a moment does: it
    /// becomes one step of undo, it is kept with the photo, and the preview is rendered at the
    /// size the viewer needs.
    func settleChange() {
        guard isAdjusting else { return }
        settle?.cancel()
        settle = nil
        isAdjusting = false
        if let selection {
            history.settle(selection)
            noteAdjustmentsInLibrary(of: selection.url)
        }
        requestRender()
    }

    /// Puts back the adjustments of a photo, for undo and redo, and shows that photo.
    private func restore(_ restored: DevelopSettings, to item: PhotoItem) {
        guard photos.contains(where: { $0 === item }) else { return }
        item.settings = restored
        if item.id == selectedID {
            settings = restored
            settingsDidChange()
        } else {
            select(item)
        }
    }

    /// Gives a photo of the strip adjustments decided away from the develop screen (a recipe or
    /// a paste on a selection of the library, and their undo), without showing that photo. The
    /// caller keeps them with the photo.
    func put(_ new: DevelopSettings, on item: PhotoItem) {
        item.settings = new
        item.keptSettings = new
        guard item.id == selectedID else {
            // A photo of the strip that is not on screen shows its new look at once.
            redrawThumbnail(of: item)
            return
        }
        settle?.cancel()
        settle = nil
        isAdjusting = false
        settings = new
        seenSettings = new
        // The next change starts from here.
        history.follow(item)
        sources?.settingsDidChange(new)
        requestRender()
    }

    /// Lets a preview that takes long through, once the settled one has been on screen for a
    /// while without the settings changing again.
    private func releaseSlowPreviewLater() {
        guard slowPreviewRelease == nil else { return }
        slowPreviewRelease = Task { [weak self] in
            guard let delay = self?.slowPreviewDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            slowPreviewRelease = nil
            holdsSlowPreview = false
            // Also while a render is running: it may be the standard preview standing in, which
            // would otherwise stay on screen in place of the one the viewer needs.
            if previewIsDraft || renderLoop != nil {
                requestRender()
            }
        }
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
        let longSide = sources.longSide(framedBy: renderedCrop)
        let current = previewDimension(photoLongSide: longSide)
        displayedLongSide = Double(longSide) * zoom.scale
        if previewDimension(photoLongSide: longSide) != current {
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
            let settings = renderedSettings
            let longSide = sources.longSide(framedBy: settings.crop)
            let dimension = nextRenderDimension(photoLongSide: longSide)
            let isDraft = dimension != previewDimension(photoLongSide: longSide)
            do {
                // The photo is decoded at the size of the preview: the engine scales nothing.
                let source = try await sources.source(dimension: dimension, settings: settings)
                let developed = try await renderer.render(
                    source, settings: settings, quality: .preview(maxDimension: 0),
                )
                // Drop the frame if another photo was selected meanwhile.
                if generation == loadGeneration {
                    preview = developed
                    previewCrop = settings.crop
                    previewIsDraft = isDraft
                    Self.renderLog.debug("\(self.renderSummary, privacy: .public)")
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
            // The whole photo shown while a frame is chosen is not the photo's look.
            if !isCropping {
                refreshSelectedThumbnail()
            }
            sources?.prepare(lighterDimension: Self.draftPreviewDimension, settings: renderedSettings)
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
}
