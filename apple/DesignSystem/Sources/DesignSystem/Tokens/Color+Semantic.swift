import SwiftUI

// Semantic colors live in Resources/Colors.xcassets. Usage: `Color.DS.viewerSurround`.
//
// The app is always dark (colors are judged against a neutral dark interface),
// so each color has a single appearance.

public extension Color {
    enum DS {
        /// Names of every color in the catalog, for the tests that check they resolve.
        public static let names = ["viewerSurround", "thumbnailPlaceholder", "hairline", "controlTint"]

        /// The neutral grey around the photo in the viewer.
        public static let viewerSurround = Color("viewerSurround", bundle: .module)
        /// Behind a thumbnail while its image loads.
        public static let thumbnailPlaceholder = Color("thumbnailPlaceholder", bundle: .module)
        /// Thin outlines that separate an image from the interface.
        public static let hairline = Color("hairline", bundle: .module)
        /// The tint of the system's controls (a switch that is on, the filled part of a slider):
        /// a gray, so nothing saturated sits next to the photo.
        public static let controlTint = Color("controlTint", bundle: .module)
    }
}
