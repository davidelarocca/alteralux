import AlteraluxKit
import CoreGraphics
import Foundation
import Observation

/// One photo in the strip, with its own adjustments.
@MainActor
@Observable
final class PhotoItem: Identifiable {
    let id = UUID()
    let url: URL
    var settings: DevelopSettings
    /// The adjustments as they are kept with the photo, or as it was opened if none are yet.
    var keptSettings: DevelopSettings
    /// Whether adjustments are kept with the photo: what its mark in the strip says, as the
    /// library's grid says it. A photo that was only opened and looked at has none.
    var hasAdjustments: Bool
    var thumbnail: CGImage?
    /// The photo's Finder tags, for a photo the library does not list: the library reads the
    /// tags of its own (`AppModel.tags(of:)`).
    var tags: [FinderTag] = []
    /// Whether the app holds a security-scoped access on `url` to release.
    let isScoped: Bool

    var name: String {
        url.lastPathComponent
    }

    init(url: URL, settings: DevelopSettings, isScoped: Bool, hasAdjustments: Bool = false) {
        self.url = url
        self.settings = settings
        keptSettings = settings
        self.hasAdjustments = hasAdjustments
        self.isScoped = isScoped
    }
}
