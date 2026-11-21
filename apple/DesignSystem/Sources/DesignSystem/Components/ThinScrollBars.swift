import AppKit
import SwiftUI

public extension View {
    /// Gives the scroll view this is applied to (a `Form`, a `List`, a `ScrollView`) the system's
    /// thin scroll bars, which show only while it scrolls, even with a mouse connected: the same
    /// bars as the photo viewer's. With a mouse, the system otherwise draws wide bars that stay.
    func thinScrollBars() -> some View {
        background(ThinScrollBars())
    }
}

/// Finds the scroll view drawn where it is and keeps its scroll bars the thin ones.
private struct ThinScrollBars: NSViewRepresentable {
    func makeNSView(context _: Context) -> ThinScrollBarsView {
        ThinScrollBarsView()
    }

    func updateNSView(_ view: ThinScrollBarsView, context _: Context) {
        view.apply()
    }
}

final class ThinScrollBarsView: NSView {
    private weak var scrollView: NSScrollView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The system sets the style again when the user's preference changes, or a mouse is
        // plugged in: set it back after it.
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferenceDidChange),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The scroll view is laid out around this view once both are in the window.
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    @objc private func preferenceDidChange(_: Notification) {
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    override func layout() {
        super.layout()
        apply()
    }

    func apply() {
        if scrollView == nil {
            scrollView = Self.scrollView(around: self)
        }
        guard let scrollView, scrollView.scrollerStyle != .overlay else { return }
        scrollView.scrollerStyle = .overlay
    }

    /// The smallest scroll view that covers the middle of `view`, among the views near it: the
    /// one the modifier was applied to, drawn behind or around it.
    static func scrollView(around view: NSView) -> NSScrollView? {
        if let enclosing = view.enclosingScrollView {
            return enclosing
        }
        guard view.window != nil else { return nil }
        let middle = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        var ancestor = view.superview
        while let current = ancestor {
            let found = scrollViews(in: current).filter { scrollView in
                scrollView.convert(scrollView.bounds, to: nil).contains(middle)
            }
            if let smallest = found.min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
                return smallest
            }
            ancestor = current.superview
        }
        return nil
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { subview -> [NSScrollView] in
            if let scrollView = subview as? NSScrollView {
                return [scrollView]
            }
            return scrollViews(in: subview)
        }
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
