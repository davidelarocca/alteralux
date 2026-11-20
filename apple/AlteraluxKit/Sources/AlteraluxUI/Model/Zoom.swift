// The zoom of the viewer: what the app asks of it and what it reports back.

/// How the photo is scaled in the viewer.
enum ZoomCommand: Equatable {
    case fit
    case actualSize
    case zoomIn
    case zoomOut
    /// A scale relative to the photo's actual pixels (1 = 100%).
    case scale(Double)
}

/// What the viewer reports about how the photo is scaled.
struct ViewerZoom: Equatable {
    /// The scale relative to the photo's actual pixels (1 = 100%).
    var scale = 0.0
    /// The scale that fits the whole photo in the viewer as it is now.
    var fitScale = 0.0
    /// Whether the photo is kept fitted to the viewer as the window resizes.
    var isFitted = true
}

/// The two zooms the user asks for by name.
enum ZoomPreset: Hashable {
    case fit
    case actualSize
}
