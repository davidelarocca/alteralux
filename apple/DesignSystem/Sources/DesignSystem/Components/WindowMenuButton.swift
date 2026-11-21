import AppKit
import SwiftUI

/// One entry of the menu of a `WindowMenuButton`.
public enum WindowMenuEntry {
    /// A choice, with a line of context under its title.
    case item(_ title: String, subtitle: String? = nil, isEnabled: Bool = true, action: @MainActor () -> Void)
    /// One option among others, with a checkmark when it is the one chosen ("Sort By: Name").
    case choice(_ title: String, isChosen: Bool, isEnabled: Bool = true, action: @MainActor () -> Void)
    /// The title of the group of entries under it, as a menu's section has it ("Sort By").
    case heading(_ title: String)
    /// A choice that opens a menu of its own.
    case submenu(_ title: String, isEnabled: Bool = true, entries: [WindowMenuEntry])
    /// A line that says something and cannot be chosen ("No recipes").
    case note(_ title: String)
    case separator
}

/// A button, in the toolbar, that opens the system's menu under itself, inside the window.
///
/// A SwiftUI `Menu` opens from its button's leading edge toward the trailing one, so near the
/// window's trailing edge it passes it. This one opens the same system menu under the point
/// clicked, moved toward the leading side as far as it needs to stay inside the window. The
/// entries are asked for when it opens, so they are always current: a group of choices under a
/// heading shows the one chosen with a checkmark, as an inline `Picker` in a `Menu` does.
public struct WindowMenuButton<Label: View>: View {
    private let entries: () -> [WindowMenuEntry]
    private let label: Label

    public init(entries: @escaping () -> [WindowMenuEntry], @ViewBuilder label: () -> Label) {
        self.entries = entries
        self.label = label()
    }

    public var body: some View {
        Button {
            WindowMenu.popUp(entries())
        } label: {
            label
        }
    }
}

/// Opens a system menu inside the key window.
@MainActor
enum WindowMenu {
    /// Room kept between the menu and the window's edge, in points.
    nonisolated private static let margin = Spacing.s

    static func popUp(_ entries: [WindowMenuEntry]) {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let menu = makeMenu(entries)
        // Under the toolbar, from where the button was clicked; from the trailing side when the
        // menu was opened from the keyboard.
        let bounds = view.bounds
        let width = menu.size.width
        let event = NSApp.currentEvent
        let clickX = event.map { view.convert($0.locationInWindow, from: nil).x } ?? bounds.maxX
        let leading = leadingEdge(of: width, under: clickX, in: bounds.width)
        // The edge of the content under the toolbar: the top of the content's rectangle.
        let content = view.convert(window.contentLayoutRect, from: nil)
        let top = view.isFlipped ? content.minY : content.maxY
        menu.popUp(positioning: nil, at: NSPoint(x: leading, y: top), in: view)
    }

    /// Where a menu `width` wide opens under a click at `clickX`, in a window `windowWidth` wide:
    /// centered under the click, moved as far as it needs to keep inside the window's edges.
    nonisolated static func leadingEdge(of width: CGFloat, under clickX: CGFloat, in windowWidth: CGFloat) -> CGFloat {
        let leading = min(clickX - width / 2, windowWidth - width - margin)
        return max(leading, margin)
    }

    static func makeMenu(_ entries: [WindowMenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            menu.addItem(makeItem(entry))
        }
        return menu
    }

    private static func makeItem(_ entry: WindowMenuEntry) -> NSMenuItem {
        switch entry {
        case let .item(title, subtitle, isEnabled, action):
            let item = ActionMenuItem(title: title, action: action)
            item.subtitle = subtitle
            item.isEnabled = isEnabled
            return item
        case let .choice(title, isChosen, isEnabled, action):
            let item = ActionMenuItem(title: title, action: action)
            item.state = isChosen ? .on : .off
            item.isEnabled = isEnabled
            return item
        case let .heading(title):
            return .sectionHeader(title: title)
        case let .submenu(title, isEnabled, entries):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = makeMenu(entries)
            item.isEnabled = isEnabled
            return item
        case let .note(title):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .separator:
            return .separator()
        }
    }
}

/// A menu item that runs a closure when it is chosen.
@MainActor
private final class ActionMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, action: @escaping @MainActor () -> Void) {
        run = action
        super.init(title: title, action: #selector(choose), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func choose() {
        run()
    }
}

#Preview("Choices under headings") {
    WindowMenuButton {
        [
            .heading("Sort By"),
            .choice("Name", isChosen: true) {},
            .choice("Date", isChosen: false) {},
            .heading("Order"),
            .choice("Ascending", isChosen: false) {},
            .choice("Descending", isChosen: true) {},
            .separator,
            .item("Clear Filters", isEnabled: false) {},
        ]
    } label: {
        Label("Filter and Sort", systemImage: "line.3.horizontal.decrease")
    }
    .padding(Spacing.xl)
}

#Preview("Window menu button") {
    WindowMenuButton {
        [
            .item("Portra at Dusk", subtitle: "Kodak Portra 400 → Portra Endura") {},
            .item("No Grain") {},
            .separator,
            .item("Save as New Recipe…") {},
            .submenu("Rename", entries: [.item("Portra at Dusk") {}]),
            .submenu("Delete", isEnabled: false, entries: []),
        ]
    } label: {
        Label("Recipe", systemImage: "camera.filters")
    }
    .padding(Spacing.xl)
}
