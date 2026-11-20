// The size the preview is rendered at, for how large the viewer shows the photo.

/// Picks the long side of the preview from the size of the photo on screen.
///
/// A render costs in proportion to its pixels, so the preview is no larger than the viewer can
/// show: the standard size while the photo is small on screen, larger ones in steps as it
/// grows, and the photo's own resolution only when the viewer shows about that many pixels.
enum PreviewSize {
    /// Long side of the standard preview, in pixels: the smallest one shown once the settings
    /// stay still.
    static let standard = 2048
    /// Larger previews grow by this much. Steps, because the engine scales the photo once per
    /// size (about 250 ms at 24 MP) and keeps few sizes.
    static let step = 512
    /// A preview is shown up to this much larger than it is before a larger one is rendered.
    static let enlargement = 1.15
    /// The largest preview rendered straight after the lighter one. A larger one takes several
    /// tenths of a second or more, so the standard preview is shown first.
    static let directLimit = 3072

    /// The long side to render, in pixels (0 = the photo's full resolution).
    ///
    /// - Parameters:
    ///   - displayedLongSide: the long side of the photo as the viewer shows it, in display
    ///     pixels; 0 before the viewer has reported.
    ///   - photoLongSide: the long side of the photo, in pixels.
    static func dimension(displayedLongSide: Double, photoLongSide: Int) -> Int {
        var size = standard
        while Double(size) * enlargement < displayedLongSide, size < photoLongSide {
            size += step
        }
        // A photo barely larger than the preview is rendered as it is: it costs about the same,
        // needs no scaled copy and shows its real pixels.
        return Double(size) * enlargement >= Double(photoLongSide) ? 0 : size
    }

    /// Whether a preview of `dimension` is slow enough to show the standard one first.
    static func comesAfterStandard(_ dimension: Int, photoLongSide: Int) -> Bool {
        (dimension == 0 ? photoLongSide : dimension) > directLimit
    }
}
