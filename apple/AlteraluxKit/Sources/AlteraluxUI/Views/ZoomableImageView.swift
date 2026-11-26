import AppKit
import DesignSystem
import SwiftUI

/// A zoomable, scrollable photo viewer.
///
/// Built on `NSScrollView`, so pinch to zoom, smart zoom, scrolling and
/// rubber-banding behave like every other Mac app. Its scroll bars are always the thin ones
/// that show while scrolling. A mouse's wheel zooms about the pointer, where two fingers on a
/// trackpad move the photo (told apart by the trackpad's gesture phases, not by precise
/// deltas, which smooth-scrolling mice send too); with Command held any scroll zooms (a Magic
/// Mouse scrolls as a trackpad does). A drag moves a photo larger than the view, as a hand would.
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
    /// While set, a click on the photo reports the point clicked, from its top left corner, 0 to
    /// 1 across and down, instead of moving it; the pointer is a crosshair.
    var onPick: (@MainActor (CGPoint) -> Void)?

    func makeNSView(context _: Context) -> ImageScrollView {
        ImageScrollView()
    }

    func updateNSView(_ view: ImageScrollView, context: Context) {
        view.onZoomChange = onZoomChange
        view.onPick = onPick
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
    /// See `ZoomableImageView.onPick`.
    var onPick: (@MainActor (CGPoint) -> Void)? {
        didSet {
            let isPicking = onPick != nil
            guard isPicking != (oldValue != nil) else { return }
            // A double-click would zoom between the two clicks of two points.
            doubleClick.isEnabled = !isPicking
            window?.invalidateCursorRects(for: self)
        }
    }

    private let doubleClick = NSClickGestureRecognizer()

    private let imageView = ImageLayerView()
    private var pixelSize = CGSize.zero
    /// Width in pixels of the image on screen (a preview is smaller than the photo).
    private var imagePixelWidth = CGFloat.zero
    /// While set, the photo is kept fitted to the view as the window resizes.
    private var fitsView = true
    private var reportedZoom: ViewerZoom?
    /// Where a drag of the photo began: the pointer in the window, and the visible part's origin.
    private var dragStart: (pointer: NSPoint, origin: NSPoint)?

    /// How much one step of a mouse's wheel zooms.
    private static let wheelStep = 1.1
    /// Points of a precise scroll (a smooth wheel, a trackpad with Command) that make one step of zoom.
    private static let pointsPerStep: CGFloat = 10

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

        doubleClick.target = self
        doubleClick.action = #selector(didDoubleClick)
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

    /// A mouse's wheel zooms the photo about the pointer; a trackpad's two fingers, and a wheel
    /// turned sideways, move it, as in any other view.
    override func scrollWheel(with event: NSEvent) {
        guard Self.zoomsOnScroll(event) else {
            super.scrollWheel(with: event)
            return
        }
        let steps = Self.wheelSteps(of: event)
        guard steps != 0 else { return }
        let fit = fitMagnification() ?? minMagnification
        let wanted = magnification * pow(Self.wheelStep, steps)
        if wanted <= fit {
            // Back to the whole photo, which then follows the window again.
            fitsView = true
            zoomToFit()
            return
        }
        let pointer = contentView.convert(event.locationInWindow, from: nil)
        zoom(to: min(wanted, maxMagnification), centeredAt: pointer)
    }

    /// Whether a scroll zooms: one from a mouse's wheel, or any with Command held. A trackpad's
    /// scroll (and a Magic Mouse's) is a gesture, with a phase and then momentum, and moves the
    /// photo; a wheel's has neither, even a wheel that scrolls smoothly, in points, as many mice
    /// do: precise deltas alone do not tell a trackpad.
    static func zoomsOnScroll(_ event: NSEvent) -> Bool {
        guard event.scrollingDeltaY != 0 else { return false }
        let isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        return !isGesture || event.modifierFlags.contains(.command)
    }

    /// Steps of the wheel turned away from the user, which zoom in; the other way they zoom
    /// out, whatever the direction of scrolling set in System Settings.
    static func wheelSteps(of event: NSEvent) -> CGFloat {
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        return event.hasPreciseScrollingDeltas ? delta / pointsPerStep : delta
    }

    /// Whether the photo is larger than the view, so a drag can move it.
    private var canPan: Bool {
        let document = imageView.frame.size
        let visible = contentView.bounds.size
        return document.width > visible.width + 0.5 || document.height > visible.height + 0.5
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onPick != nil {
            addCursorRect(contentView.frame, cursor: .crosshair)
        } else if canPan {
            addCursorRect(contentView.frame, cursor: .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let onPick {
            if let point = pickedPoint(of: event) {
                onPick(point)
            }
            return
        }
        guard canPan else {
            super.mouseDown(with: event)
            return
        }
        dragStart = (event.locationInWindow, contentView.bounds.origin)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else {
            super.mouseDragged(with: event)
            return
        }
        // The photo follows the pointer: the visible part moves the other way, in the
        // photo's own points.
        let moved = NSPoint(
            x: (event.locationInWindow.x - dragStart.pointer.x) / magnification,
            y: (event.locationInWindow.y - dragStart.pointer.y) / magnification,
        )
        let flip: CGFloat = imageView.isFlipped ? -1 : 1
        var visible = contentView.bounds
        visible.origin = NSPoint(x: dragStart.origin.x - moved.x, y: dragStart.origin.y - moved.y * flip)
        contentView.scroll(to: contentView.constrainBoundsRect(visible).origin)
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else {
            super.mouseUp(with: event)
            return
        }
        dragStart = nil
        NSCursor.pop()
    }

    /// Where `event` is on the photo, from its top left corner, 0 to 1 across and down; `nil`
    /// outside it.
    private func pickedPoint(of event: NSEvent) -> CGPoint? {
        let bounds = imageView.bounds
        let point = imageView.convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        let down = (point.y - bounds.minY) / bounds.height
        return CGPoint(x: (point.x - bounds.minX) / bounds.width, y: imageView.isFlipped ? down : 1 - down)
    }

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
        // The hand that moves the photo shows only while it is larger than the view.
        window?.invalidateCursorRects(for: self)
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
