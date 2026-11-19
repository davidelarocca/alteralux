import AppKit
import Observation
import SpektrafilmEngine
import SpektrafilmKit
import UniformTypeIdentifiers

/// The state of the app: the film catalogue, the open photo, its settings and
/// the latest developed preview.
@MainActor
@Observable
final class AppModel {
    // MARK: Catalogue

    private(set) var films: [StockInfo] = []
    private(set) var papers: [StockInfo] = []

    // MARK: Open photo

    private(set) var photo: LoadedImage?
    private(set) var photoName = ""
    private(set) var preview: DevelopedImage?
    var settings = DevelopSettings()
    var exportOptions = ExportOptions()

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

    /// Long side of the live preview, in pixels.
    private let previewDimension = 2048

    private var renderer: FilmRenderer?
    private var renderLoop: Task<Void, Never>?
    private var needsRender = false
    /// The security-scoped URL of the open photo, kept accessible so its
    /// metadata can be read again at export time.
    private var accessedURL: URL?

    var canExport: Bool { photo != nil && !isExporting }

    var selectedFilm: StockInfo? { films.first { $0.id == settings.filmID } }
    var selectedPaper: StockInfo? { papers.first { $0.id == settings.paperID } }

    /// "Portra 400 on Portra Endura", shown under the window title.
    var materialsSummary: String {
        guard photo != nil, let film = selectedFilm else { return "" }
        if settings.scanFilm { return film.displayName }
        guard let paper = selectedPaper else { return film.displayName }
        return "\(film.displayName) → \(paper.displayName)"
    }

    /// Backend and timing of the last preview render, for diagnostics.
    var renderSummary: String {
        guard let stats = preview?.stats else { return "" }
        return "\(stats.backend) · \(Int(stats.totalMs.rounded())) ms"
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

    // MARK: - Opening

    func open(_ url: URL) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            let isScoped = url.startAccessingSecurityScopedResource()
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(url)
                }.value
                accessedURL?.stopAccessingSecurityScopedResource()
                accessedURL = isScoped ? url : nil
                photo = loaded
                photoName = url.lastPathComponent
                preview = nil
                requestRender()
            } catch {
                if isScoped { url.stopAccessingSecurityScopedResource() }
                alertMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Settings

    /// Applies what follows from choosing a film: slides are scanned directly,
    /// negatives are printed on the paper their profile recommends.
    func filmDidChange() {
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

    // MARK: - Rendering

    /// Renders the preview with the current settings. Calls made while a
    /// render is running collapse into one follow-up render with the latest
    /// settings, so dragging a slider never queues up stale frames.
    func requestRender() {
        guard photo != nil, renderer != nil else { return }
        needsRender = true
        guard renderLoop == nil else { return }
        renderLoop = Task { await runRenderLoop() }
    }

    private func runRenderLoop() async {
        isRendering = true
        while needsRender, let photo, let renderer {
            needsRender = false
            do {
                preview = try await renderer.render(
                    photo, settings: settings, quality: .preview(maxDimension: previewDimension))
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        isRendering = false
        renderLoop = nil
    }

    // MARK: - Export

    func export() async {
        guard let photo, let renderer, !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportOptions.format.contentType]
        panel.canCreateDirectories = true
        let baseName = photo.url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName) \(settings.filmID).\(exportOptions.format.fileExtension)"
        guard await panel.begin() == .OK, let destination = panel.url else { return }

        isExporting = true
        defer { isExporting = false }
        let options = exportOptions
        do {
            let developed = try await renderer.render(photo, settings: settings, quality: .full)
            try await Task.detached(priority: .userInitiated) {
                try ImageExporter.write(
                    developed, to: destination, options: options, originalURL: photo.url)
            }.value
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
