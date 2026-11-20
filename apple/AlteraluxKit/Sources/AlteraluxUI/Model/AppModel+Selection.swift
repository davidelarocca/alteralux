import Foundation

// Moving through the photos of the strip.

extension AppModel {
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
