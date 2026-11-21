import AppKit
import Testing
@testable import AlteraluxUI

@MainActor
struct ViewerTests {
    /// Mipmaps are built on the main thread for every new image: the viewer asks for them only
    /// where they change the picture.
    @Test func mipmapsAreBuiltOnlyBelowHalfSize() {
        // A preview fitted in the window is shown near its own size.
        #expect(!ImageScrollView.needsMipmaps(imagePixels: 2048, displayedPixels: 1800))
        #expect(!ImageScrollView.needsMipmaps(imagePixels: 2048, displayedPixels: 1024))
        // A full-resolution photo reduced to less than half.
        #expect(ImageScrollView.needsMipmaps(imagePixels: 6000, displayedPixels: 2400))
        // Nothing is laid out yet.
        #expect(!ImageScrollView.needsMipmaps(imagePixels: 2048, displayedPixels: 0))
    }

    /// The photo's scroll bars are the thin ones that show while scrolling, even when a mouse
    /// makes the system ask for the wide ones that stay.
    @Test func scrollBarsStayThin() {
        let viewer = ImageScrollView()
        #expect(viewer.scrollerStyle == .overlay)
        viewer.scrollerStyle = .legacy
        #expect(viewer.scrollerStyle == .overlay)
        #expect(viewer.scrollerKnobStyle == .light)
    }

    /// A mouse's wheel zooms, in steps or smoothly in points as many mice scroll. A trackpad's
    /// scroll is a gesture, with phases, and moves the photo unless Command is held. A smooth
    /// wheel was taken for a trackpad when precise deltas told them apart.
    @Test func aWheelZoomsAndATrackpadMoves() throws {
        let wheel = try #require(Self.scroll(lines: 2))
        #expect(!wheel.hasPreciseScrollingDeltas && ImageScrollView.zoomsOnScroll(wheel))
        #expect(ImageScrollView.wheelSteps(of: wheel) * (wheel.isDirectionInvertedFromDevice ? -1 : 1) == 2)
        let smoothWheel = try #require(Self.scroll(points: 20))
        #expect(smoothWheel.hasPreciseScrollingDeltas && ImageScrollView.zoomsOnScroll(smoothWheel))
        let trackpad = try #require(Self.scroll(points: 20, phase: 2))
        #expect(!trackpad.phase.isEmpty && !ImageScrollView.zoomsOnScroll(trackpad))
        let withCommand = try #require(Self.scroll(points: 20, flags: .maskCommand, phase: 2))
        #expect(ImageScrollView.zoomsOnScroll(withCommand))
    }

    /// Two steps of the wheel over a photo in a window zoom it in.
    @Test func theWheelZoomsThePhotoIn() throws {
        let (window, viewer) = try Self.viewerInAWindow()
        let fitted = viewer.magnification
        // Two steps away from the user, whatever the direction of scrolling set on this Mac.
        let away = try #require(Self.scroll(lines: 2))
        let wheel = ImageScrollView.wheelSteps(of: away) > 0 ? away : try #require(Self.scroll(lines: -2))
        viewer.scrollWheel(with: wheel)
        #expect(abs(viewer.magnification - fitted * 1.1 * 1.1) < 0.001)
        // The viewer is laid out in its window until the end.
        withExtendedLifetime(window) {}
    }

    /// A drag moves a photo larger than the view with the pointer: dragged down, it shows more
    /// of its top.
    @Test func aDragMovesALargePhoto() throws {
        let (window, viewer) = try Self.viewerInAWindow()
        viewer.perform(.actualSize)
        let before = viewer.contentView.bounds.origin
        for (type, height) in [(NSEvent.EventType.leftMouseDown, 100.0), (.leftMouseDragged, 50), (.leftMouseUp, 50)] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 300, y: height), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
            ))
            switch type {
            case .leftMouseDown: viewer.mouseDown(with: event)
            case .leftMouseDragged: viewer.mouseDragged(with: event)
            default: viewer.mouseUp(with: event)
            }
        }
        // Window coordinates go up: the pointer went 50 pt down, the visible part went up.
        let moved = viewer.contentView.bounds.origin
        #expect(abs(moved.x - before.x) < 0.001 && abs((moved.y - before.y) * viewer.magnification - 50) < 0.5)
    }

    /// A viewer in a 600 by 400 window, showing a 4000 by 3000 photo fitted.
    private static func viewerInAWindow() throws -> (NSWindow, ImageScrollView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
            backing: .buffered, defer: false,
        )
        let viewer = ImageScrollView()
        window.contentView = viewer
        let context = CGContext(
            data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
        let image = try #require(context?.makeImage())
        viewer.setImage(image, pixelSize: CGSize(width: 4000, height: 3000))
        viewer.layoutSubtreeIfNeeded()
        return (window, viewer)
    }

    private static func scroll(lines: Int32) -> NSEvent? {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
            .flatMap(NSEvent.init(cgEvent:))
    }

    /// A scroll in points; with `phase` (2: changed), part of a trackpad's gesture.
    private static func scroll(points: Int32, flags: CGEventFlags = [], phase: Int64 = 0) -> NSEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: points, wheel2: 0, wheel3: 0) else { return nil }
        event.flags = flags
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        return NSEvent(cgEvent: event)
    }
}
