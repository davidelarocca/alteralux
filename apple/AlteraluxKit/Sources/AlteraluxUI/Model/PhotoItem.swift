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
    var thumbnail: CGImage?
    /// Whether the app holds a security-scoped access on `url` to release.
    let isScoped: Bool

    var name: String {
        url.lastPathComponent
    }

    init(url: URL, settings: DevelopSettings, isScoped: Bool) {
        self.url = url
        self.settings = settings
        keptSettings = settings
        self.isScoped = isScoped
    }
}
