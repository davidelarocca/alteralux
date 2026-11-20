import AlteraluxEngine
import AlteraluxKit
import Foundation

// The film and the paper of the selected photo: what they are, choosing them, and what follows
// from the choice.

extension AppModel {
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
        hasPhoto ? materials(of: settings) : ""
    }

    /// The film and the paper of `settings` as the user reads them: "Portra 400 → Portra Endura",
    /// or the film alone when it is scanned directly.
    func materials(of settings: DevelopSettings) -> String {
        guard let film = films.first(where: { $0.id == settings.filmID }) else { return "" }
        guard !settings.scanFilm, let paper = papers.first(where: { $0.id == settings.paperID }) else {
            return film.displayName
        }
        return "\(film.displayName) → \(paper.displayName)"
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

    /// The name proposed for an exported file: the photo's name, the film as the user reads it,
    /// and the format's extension ("IMG_0042 Kodak Portra 400.jpg").
    nonisolated static func exportFileName(
        source: URL, film: String, format: ExportOptions.Format,
    ) -> String {
        "\(exportName(source: source, film: film)).\(format.fileExtension)"
    }

    /// The name of an exported file without its extension: the photo's name and the film.
    nonisolated static func exportName(source: URL, film: String) -> String {
        let baseName = source.deletingPathExtension().lastPathComponent
        // A film's name must not read as a path in the save panel.
        let filmName = film.replacing("/", with: "-").replacing(":", with: "-")
        return "\(baseName) \(filmName)"
    }
}
