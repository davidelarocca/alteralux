import CoreGraphics
import Foundation
import os

// The selected photo, what can be done with it, and moving through the strip.

extension AppModel {
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

    /// The size of the photo on screen, in pixels, once it is open: framed as its preview is.
    var photoSize: CGSize? {
        sources.map { sources in
            previewCrop?.framedSize(of: sources.decoder.size) ?? sources.decoder.size
        }
    }

    /// Where each preview render is logged, for diagnostics: the screen does not show it.
    /// `log stream --level debug --predicate 'category == "render"'` follows it.
    static let renderLog = Logger(subsystem: "io.github.davidelarocca.alteralux", category: "render")

    /// Backend and timing of the last preview render, for diagnostics.
    var renderSummary: String {
        guard let preview else { return "" }
        return "\(preview.stats.backend) · \(preview.width) × \(preview.height) · "
            + "\(Int(preview.stats.totalMs.rounded())) ms"
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
}
