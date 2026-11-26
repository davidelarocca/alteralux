import AppKit
import SwiftUI

public extension View {
    /// Opens the system's share picker (`NSSharingServicePicker`) for `items`, pointing at this
    /// view, when they are set, and sets them back to `nil`.
    ///
    /// For Share… in a context menu: a `ShareLink` there has no view to point at, and macOS opens
    /// its picker at the top of the window, far from what was clicked. The view this is attached
    /// to keeps the place the menu was opened from.
    ///
    /// - Parameter edge: the side of this view the picker opens on: the top for something near
    ///   the bottom edge of a window.
    func sharePicker(items: Binding<[URL]?>, edge: NSRectEdge = .maxY) -> some View {
        modifier(SharePickerModifier(items: items, edge: edge))
    }
}

/// Reads the items, so the anchor is drawn again whenever they are set.
private struct SharePickerModifier: ViewModifier {
    @Binding var items: [URL]?
    let edge: NSRectEdge

    func body(content: Content) -> some View {
        content.background(SharePickerAnchor(items: items, edge: edge) { items = nil })
    }
}

/// An empty view as large as the one it lies behind: the anchor of the picker.
private struct SharePickerAnchor: NSViewRepresentable {
    let items: [URL]?
    let edge: NSRectEdge
    /// Gives the items back once the picker is asked for.
    let done: () -> Void

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        guard let items, !items.isEmpty, !coordinator.isOpening else { return }
        coordinator.isOpening = true
        // In the run loop's default mode, so after the menu that asked has closed: a picker shown
        // while the menu tracks is dismissed with it.
        RunLoop.main.perform(inModes: [.default]) {
            coordinator.isOpening = false
            done()
            guard view.window != nil else { return }
            let picker = NSSharingServicePicker(items: items)
            coordinator.picker = picker
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Keeps the picker while it is shown, and asks for it once.
    final class Coordinator {
        var picker: NSSharingServicePicker?
        var isOpening = false
    }
}

#Preview("Share picker") {
    @Previewable @State var items: [URL]?
    Button("Share…") { items = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")] }
        .sharePicker(items: $items)
        .padding(Spacing.xl)
}
