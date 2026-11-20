import AppKit
import DesignSystem
import SwiftUI

/// A zoomable, scrollable photo viewer.
///
/// Built on `NSScrollView`, so pinch to zoom, smart zoom, scrolling and
/// rubber-banding behave like every other Mac app. Its scroll bars are always the thin ones
/// that show while scrolling.
struct ZoomableImageView: NSViewRepresentable {
    let image: CGImage
    /// Size of the full-resolution photo in pixels. Zoom is measured against
    /// it, not against `image`, so the view keeps its place when a sharper
    /// preview replaces a coarser one.
    let pixelSize: CGSize
    let command: ZoomCommand
    let commandID: Int
    /// Reports how the photo is scaled, whenever that changes.
    let onZoomChange: @MainActor (ViewerZoom) -> Void

    func makeNSView(context _: Context) -> ImageScrollView {
        ImageScrollView()
    }

    func updateNSView(_ view: ImageScrollView, context: Context) {
        view.onZoomChange = onZoomChange
        view.setImage(image, pixelSize: pixelSize)
        if context.coordinator.lastCommandID != commandID {
            context.coordinator.lastCommandID = commandID
            view.perform(command)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCommandID = -1
    }
}

final class ImageScrollView: NSScrollView {
    var onZoomChange: (@MainActor (ViewerZoom) -> Void)?

    private let imageView = ImageLayerView()
    private var pixelSize = CGSize.zero
    /// Width in pixels of the image on screen (a preview is smaller than the photo).
    private var imagePixelWidth = CGFloat.zero
    /// While set, the photo is kept fitted to the view as the window resizes.
    private var fitsView = true
    private var reportedZoom: ViewerZoom?

    /// Space left around a fitted photo, in points.
    private static let padding = Spacing.xl

    init() {
        super.init(frame: .zero)
        let clipView = CenteringClipView()
        clipView.drawsBackground = false
        contentView = clipView
        documentView = imageView
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        // The photo sits on the viewer's dark surround in light and dark appearance alike.
        scrollerKnobStyle = .light
        allowsMagnification = true
        minMagnification = 0.01
        maxMagnification = 8

        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(willStartMagnify),
            name: NSScrollView.willStartLiveMagnifyNotification, object: self,
        )
        center.addObserver(
            self, selector: #selector(didEndMagnify),
            name: NSScrollView.didEndLiveMagnifyNotification, object: self,
        )

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(didDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Thin scroll bars that show only while the photo moves, as with a trackpad, even with a
    /// mouse connected: wide bars that stay would take a band off the photo. The system sets
    /// the style again when its preference changes, so every style it sets is kept overlay.
    override var scrollerStyle: NSScroller.Style {
        didSet {
            if scrollerStyle != .overlay {
                scrollerStyle = .overlay
            }
        }
    }

    func setImage(_ image: CGImage, pixelSize newSize: CGSize) {
        imageView.image = image
        // Only a full-resolution image has real pixels worth showing unsmoothed.
        imageView.showsRealPixels = CGFloat(image.width) >= newSize.width - 1
        imagePixelWidth = CGFloat(image.width)
        if newSize != pixelSize {
            // A different photo: start fitted.
            pixelSize = newSize
            fitsView = true
            updateDocumentSize()
            zoomToFit()
        }
        updateFiltering()
    }

    /// Whether an image needs mipmaps to be shown at a size: only when it is reduced to less
    /// than half, where plain linear filtering skips pixels and the picture aliases.
    ///
    /// Core Animation builds the mipmaps on the main thread when the image is set, about 30 ms
    /// for a preview: at the sizes a preview is normally shown, that would be paid on every
    /// update for nothing.
    static func needsMipmaps(imagePixels: CGFloat, displayedPixels: CGFloat) -> Bool {
        displayedPixels > 0 && imagePixels > displayedPixels * 2
    }

    private func updateFiltering() {
        // The document is the photo at one pixel per display pixel at magnification 1.
        imageView.usesMipmaps = Self.needsMipmaps(
            imagePixels: imagePixelWidth, displayedPixels: pixelSize.width * magnification,
        )
    }

    func perform(_ command: ZoomCommand) {
        switch command {
        case .fit:
            fitsView = true
            zoomToFit()
        case .actualSize:
            zoom(to: 1)
        case .zoomIn:
            zoom(to: min(magnification * 1.5, maxMagnification))
        case .zoomOut:
            zoom(to: max(magnification / 1.5, minMagnification))
        case let .scale(scale):
            zoom(to: min(max(CGFloat(scale), minMagnification), maxMagnification))
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        if fitsView {
            zoomToFit()
        } else {
            // The scale that fits follows the window.
            reportZoom()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDocumentSize()
        if fitsView {
            zoomToFit()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDocumentSize()
        if fitsView {
            zoomToFit()
        }
    }

    /// Sizes the document so that magnification 1 shows one photo pixel per
    /// display pixel.
    private func updateDocumentSize() {
        let backingScale = window?.backingScaleFactor ?? 2
        imageView.setFrameSize(
            NSSize(width: pixelSize.width / backingScale, height: pixelSize.height / backingScale),
        )
    }

    /// The magnification that shows the whole photo, or `nil` before the view has a size.
    private func fitMagnification() -> CGFloat? {
        let document = imageView.frame.size
        guard document.width > 0, document.height > 0, bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        let available = NSSize(
            width: max(bounds.width - 2 * Self.padding, 1),
            height: max(bounds.height - 2 * Self.padding, 1),
        )
        // Never enlarge a small photo beyond its actual size.
        return min(available.width / document.width, available.height / document.height, 1)
    }

    private func zoomToFit() {
        guard let fit = fitMagnification() else { return }
        minMagnification = min(fit, AppModel.zoomScaleRange.lowerBound)
        if abs(magnification - fit) > 0.0001 {
            magnification = fit
        }
        reportZoom()
    }

    private func zoom(to value: CGFloat, centeredAt point: NSPoint? = nil) {
        fitsView = false
        let center = point ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(value, centeredAt: center)
        reportZoom()
    }

    // MARK: Events

    @objc private func willStartMagnify(_: Notification) {
        fitsView = false
    }

    @objc private func didEndMagnify(_: Notification) {
        reportZoom()
    }

    /// Double-click toggles between fitted and actual size at the click point.
    @objc private func didDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        if fitsView {
            zoom(to: 1, centeredAt: recognizer.location(in: contentView))
        } else {
            fitsView = true
            zoomToFit()
        }
    }

    /// Whether two reports say the same to the reader: scales closer than this are one scale.
    private static func isSame(_ one: ViewerZoom, _ other: ViewerZoom) -> Bool {
        one.isFitted == other.isFitted
            && abs(one.scale - other.scale) <= 0.0001
            && abs(one.fitScale - other.fitScale) <= 0.0001
    }

    private func reportZoom() {
        updateFiltering()
        let zoom = ViewerZoom(
            scale: Double(magnification),
            fitScale: Double(fitMagnification() ?? magnification),
            isFitted: fitsView,
        )
        if let reportedZoom, Self.isSame(reportedZoom, zoom) {
            return
        }
        reportedZoom = zoom
        // Deferred: this can run during a SwiftUI update, where changing
        // observed state is not allowed.
        Task { @MainActor [weak self] in self?.onZoomChange?(zoom) }
    }
}

/// Shows a `CGImage` through its layer. Core Animation color-manages the
/// image for the display from its embedded color space.
private final class ImageLayerView: NSView {
    var image: CGImage? {
        didSet {
            if image !== oldValue {
                needsDisplay = true
            }
        }
    }

    /// Above 100%, show the photo's pixels (and its grain) unsmoothed.
    var showsRealPixels = false {
        didSet {
            if showsRealPixels != oldValue {
                needsDisplay = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Reduce the image through mipmaps. See `ImageScrollView.needsMipmaps`.
    var usesMipmaps = false {
        didSet {
            if usesMipmaps != oldValue {
                needsDisplay = true
            }
        }
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.minificationFilter = usesMipmaps ? .trilinear : .linear
        layer.magnificationFilter = showsRealPixels ? .nearest : .linear
    }
}

/// Keeps the document centered when it is smaller than the visible area.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let document = documentView.frame
        if rect.width > document.width {
            rect.origin.x = document.midX - rect.width / 2
        }
        if rect.height > document.height {
            rect.origin.y = document.midY - rect.height / 2
        }
        return rect
    }
}
