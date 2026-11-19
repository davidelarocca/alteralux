import AppKit
import DesignSystem
import SwiftUI

/// A zoomable, scrollable photo viewer.
///
/// Built on `NSScrollView`, so pinch to zoom, smart zoom, scrolling and
/// rubber-banding behave like every other Mac app.
struct ZoomableImageView: NSViewRepresentable {
    let image: CGImage
    /// Size of the full-resolution photo in pixels. Zoom is measured against
    /// it, not against `image`, so the view keeps its place when a sharper
    /// preview replaces a coarser one.
    let pixelSize: CGSize
    let command: ZoomCommand
    let commandID: Int
    /// Reports the scale relative to actual pixels (1 = 100%).
    let onScaleChange: @MainActor (Double) -> Void

    func makeNSView(context _: Context) -> ImageScrollView {
        ImageScrollView()
    }

    func updateNSView(_ view: ImageScrollView, context: Context) {
        view.onScaleChange = onScaleChange
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
    var onScaleChange: (@MainActor (Double) -> Void)?

    private let imageView = ImageLayerView()
    private var pixelSize = CGSize.zero
    /// While set, the photo is kept fitted to the view as the window resizes.
    private var fitsView = true
    private var reportedScale = -1.0

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

    func setImage(_ image: CGImage, pixelSize newSize: CGSize) {
        imageView.image = image
        // Only a full-resolution image has real pixels worth showing unsmoothed.
        imageView.showsRealPixels = CGFloat(image.width) >= newSize.width - 1
        guard newSize != pixelSize else { return }
        // A different photo: start fitted.
        pixelSize = newSize
        fitsView = true
        updateDocumentSize()
        zoomToFit()
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
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        if fitsView {
            zoomToFit()
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

    private func zoomToFit() {
        let document = imageView.frame.size
        guard document.width > 0, document.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }
        let available = NSSize(
            width: max(bounds.width - 2 * Self.padding, 1),
            height: max(bounds.height - 2 * Self.padding, 1),
        )
        // Never enlarge a small photo beyond its actual size.
        let fit = min(available.width / document.width, available.height / document.height, 1)
        minMagnification = min(fit, 0.1)
        if abs(magnification - fit) > 0.0001 {
            magnification = fit
        }
        reportScale()
    }

    private func zoom(to value: CGFloat, centeredAt point: NSPoint? = nil) {
        fitsView = false
        let center = point ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(value, centeredAt: center)
        reportScale()
    }

    // MARK: Events

    @objc private func willStartMagnify(_: Notification) {
        fitsView = false
    }

    @objc private func didEndMagnify(_: Notification) {
        reportScale()
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

    private func reportScale() {
        let scale = Double(magnification)
        guard abs(scale - reportedScale) > 0.0001 else { return }
        reportedScale = scale
        // Deferred: this can run during a SwiftUI update, where changing
        // observed state is not allowed.
        Task { @MainActor [weak self] in self?.onScaleChange?(scale) }
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

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
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
