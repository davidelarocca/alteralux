import AppKit
import DesignSystem
import SwiftUI
import Testing

/// What a thumbnail's menu asks to share, as a view keeps it.
@MainActor
@Observable
private final class SharingRequest {
    var items: [URL]?
}

/// A thumbnail at the bottom of a window, with the picker attached.
private struct SharingHost: View {
    @Bindable var sharing: SharingRequest

    var body: some View {
        VStack {
            Spacer()
            Color.gray
                .frame(width: 80, height: 60)
                .sharePicker(items: $sharing.items)
        }
        .frame(width: 600, height: 400)
    }
}

extension WindowedTests {
    /// Share… from a thumbnail's menu asks the system's picker to open beside that thumbnail.
    /// Where it opens is measured in the built app: a test process gets no picker on screen.
    @MainActor
    struct SharePickerRequest {
        /// The items are taken once the menu has closed and given back, so a second Share…
        /// asks again.
        @Test func theItemsAreTakenAndGivenBack() {
            _ = NSApplication.shared
            let sharing = SharingRequest()
            let window = NSWindow(
                contentRect: CGRect(x: -20_000, y: -20_000, width: 600, height: 400),
                styleMask: [.borderless], backing: .buffered, defer: false,
            )
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SharingHost(sharing: sharing))
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
            defer { window.close() }
            Self.spin(0.3)

            for _ in 0 ..< 2 {
                sharing.items = [URL(fileURLWithPath: NSTemporaryDirectory())]
                Self.spin(0.5)
                #expect(sharing.items == nil, "The items are given back once the picker is asked for.")
            }
        }

        private static func spin(_ duration: TimeInterval) {
            let end = Date().addingTimeInterval(duration)
            while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.05))) }
        }
    }
}
