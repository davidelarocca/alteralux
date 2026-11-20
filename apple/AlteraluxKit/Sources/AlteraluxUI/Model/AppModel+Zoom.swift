import Foundation

// The zoom of the viewer as the zoom controls read and set it.

extension AppModel {
    /// The viewer's scale as the zoom slider reads it: its base 2 logarithm, inside the slider's range.
    var zoomLevel: Double {
        Self.zoomLevel(of: viewerZoom.scale)
    }

    /// Where the fitted photo sits on the zoom slider: its neutral point.
    var fitZoomLevel: Double {
        Self.zoomLevel(of: viewerZoom.fitScale)
    }

    /// Which of the named zooms the viewer is showing, if any.
    var zoomPreset: ZoomPreset? {
        if viewerZoom.isFitted {
            return .fit
        }
        return abs(viewerZoom.scale - 1) < Self.actualSizeTolerance ? .actualSize : nil
    }

    /// A scale counts as 100% within this distance: the readout shows whole percents.
    private static let actualSizeTolerance = 0.005

    private static func zoomLevel(of scale: Double) -> Double {
        log2(min(max(scale, zoomScaleRange.lowerBound), zoomScaleRange.upperBound))
    }

    /// Sets the zoom from the slider. A level within half a step of the fitted photo fits it, so
    /// the slider stops there and the photo follows the window again.
    func setZoomLevel(_ level: Double) {
        if viewerZoom.fitScale > 0, abs(level - fitZoomLevel) < Self.zoomLevelStep / 2 {
            zoom(.fit)
        } else {
            let clamped = min(max(level, Self.zoomLevelRange.lowerBound), Self.zoomLevelRange.upperBound)
            zoom(.scale(pow(2, clamped)))
        }
    }
}
