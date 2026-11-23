import AppKit
import SwiftUI

/// One choice of a `WindowPopUp`: the value it stands for and its title, in the reader's language.
public struct WindowPopUpOption<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String

    public var id: Value {
        value
    }

    public init(_ value: Value, title: String) {
        self.value = value
        self.title = title
    }
}

/// A choice among a few options in a form: the system's pop-up button, whose menu stays inside the
/// window.
///
/// The system opens a pop-up menu with the chosen option over the button, so part of it hangs
/// below; at the window's bottom edge it would pass it. This one is the same `NSPopUpButton`, and
/// opens its menu as the system does wherever it fits; where it would not, it moves the menu up
/// (or down) as far as it needs to stay inside the window. In a `Form` it has its title on the
/// row, as a `Picker` does; with `.labelsHidden()` only the button is drawn.
public struct WindowPopUp<Value: Hashable>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Value
    private let options: [WindowPopUpOption<Value>]

    @Environment(\.labelsVisibility) private var labelsVisibility
    @Environment(\.governedReason) private var governedReason

    public init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [WindowPopUpOption<Value>]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    public var body: some View {
        if labelsVisibility == .hidden {
            button
        } else {
            LabeledContent(title) { button }
        }
    }

    private var button: some View {
        PopUpButton(
            titles: options.map(\.title),
            selectedIndex: options.firstIndex { $0.value == selection },
            choose: { index in selection = options[index].value },
        )
        // Disabled by `governed(_:reason:)`, it says why after its title (a caller's `.help`
        // takes a hint's place).
        .accessibilityLabel(governedReason.map { Text("\(Text(title)), \(Text($0))") } ?? Text(title))
    }
}

/// The system's pop-up button, in SwiftUI.
private struct PopUpButton: NSViewRepresentable {
    let titles: [String]
    let selectedIndex: Int?
    let choose: (Int) -> Void

    func makeNSView(context _: Context) -> WindowPopUpButton {
        let button = WindowPopUpButton(frame: .zero, pullsDown: false)
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ button: WindowPopUpButton, context: Context) {
        button.controlSize = Self.controlSize(context.environment.controlSize)
        button.isEnabled = context.environment.isEnabled
        // An AppKit view does not follow SwiftUI's direction by itself: the arrows go on the
        // trailing side in every language.
        button.userInterfaceLayoutDirection = context.environment.layoutDirection == .rightToLeft
            ? .rightToLeft : .leftToRight
        button.choose = choose
        if button.itemTitles != titles {
            button.removeAllItems()
            for title in titles {
                // Added one by one: `addItems(withTitles:)` drops a title already there.
                button.addOption(title)
            }
        }
        if let selectedIndex, button.indexOfSelectedItem != selectedIndex {
            button.selectItem(at: selectedIndex)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: WindowPopUpButton, context _: Context) -> CGSize? {
        let natural = button.intrinsicContentSize
        // As wide as the option it shows, as the system's picker in a form: its intrinsic width
        // is the longest option's. Narrower when there is less room: the title is cut.
        let font = button.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let width = { (title: String) in (title as NSString).size(withAttributes: [.font: font]).width }
        let longest = button.itemTitles.map(width).max() ?? 0
        let shown = natural.width - longest + width(button.titleOfSelectedItem ?? "")
        return CGSize(width: min(shown.rounded(.up), proposal.width ?? shown), height: natural.height)
    }

    private static func controlSize(_ size: ControlSize) -> NSControl.ControlSize {
        switch size {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
    }
}

/// An `NSPopUpButton` whose menu opens inside its window.
final class WindowPopUpButton: NSPopUpButton {
    /// Takes the index of the option chosen.
    var choose: ((Int) -> Void)?

    /// Room kept between the menu and the window's edges, in points.
    private nonisolated static let margin = Spacing.s
    /// The menu's own space above its first row and below its last, in points.
    private nonisolated static let menuInset: CGFloat = 5
    /// How far the menu's leading edge stands before the button's, so that the titles line up.
    private nonisolated static let titleInset: CGFloat = 12

    /// Adds an option that tells the button when it is chosen, whichever way its menu was opened.
    func addOption(_ title: String) {
        let item = NSMenuItem(title: title, action: #selector(chooseItem), keyEquivalent: "")
        item.target = self
        menu?.addItem(item)
    }

    override func mouseDown(with event: NSEvent) {
        if !popUpInsideWindow() {
            super.mouseDown(with: event)
        }
    }

    /// The keyboard (Space) opens the menu through here.
    override func performClick(_ sender: Any?) {
        if !popUpInsideWindow() {
            super.performClick(sender)
        }
    }

    /// VoiceOver and other assistive technologies open the menu through here.
    override func accessibilityPerformPress() -> Bool {
        popUpInsideWindow() || super.accessibilityPerformPress()
    }

    @objc private func chooseItem(_ item: NSMenuItem) {
        select(item)
        choose?(index(of: item))
    }

    /// Opens the menu itself, moved inside the window, where the system's would pass an edge.
    /// `false` when the system's placement fits, and the system opens it.
    private func popUpInsideWindow() -> Bool {
        guard isEnabled, let menu, let window, let content = window.contentView, indexOfSelectedItem >= 0 else {
            return false
        }
        let room = window.contentLayoutRect
        let button = convert(bounds, to: nil)
        let menuSize = menu.size
        guard let placement = Self.menuTop(
            buttonMidY: button.midY, menuHeight: menuSize.height,
            rows: (menu.numberOfItems, indexOfSelectedItem), room: room.minY ... room.maxY,
        ) else {
            return false
        }
        let leading = min(
            max(button.minX - Self.titleInset, room.minX + Self.margin),
            room.maxX - menuSize.width - Self.margin,
        )
        for item in itemArray {
            item.state = item === selectedItem ? .on : .off
        }
        let location = content.convert(NSPoint(x: leading, y: placement), from: nil)
        menu.popUp(positioning: nil, at: location, in: content)
        return true
    }

    /// Where the top of the menu goes, in window coordinates (upward), when the system's
    /// placement (the chosen row over the button) would pass the room's bottom or top edge;
    /// `nil` when it fits.
    /// `rows` counts the menu's rows and says which one is chosen; `room` is the window's
    /// height under its toolbar.
    nonisolated static func menuTop(
        buttonMidY: CGFloat, menuHeight: CGFloat, rows: (count: Int, selected: Int), room: ClosedRange<CGFloat>,
    ) -> CGFloat? {
        let rowHeight = (menuHeight - 2 * menuInset) / CGFloat(max(rows.count, 1))
        let top = buttonMidY + rowHeight / 2 + CGFloat(rows.selected) * rowHeight + menuInset
        let lowest = room.lowerBound + margin
        let highest = room.upperBound - margin
        guard top - menuHeight < lowest || top > highest else { return nil }
        return min(max(top, lowest + menuHeight), highest)
    }
}

#Preview("Window pop-up") {
    @Previewable @State var format = 35
    @Previewable @State var paper = "endura"

    Form {
        WindowPopUp("Film format", selection: $format, options: [
            WindowPopUpOption(35, title: "35 mm"),
            WindowPopUpOption(120, title: "120"),
            WindowPopUpOption(45, title: "4 × 5 in"),
        ])
        WindowPopUp("Paper", selection: $paper, options: [
            WindowPopUpOption("endura", title: "Kodak Professional Portra Endura"),
            WindowPopUpOption("crystal", title: "Fujicolor Crystal Archive"),
        ])
        .labelsHidden()
        WindowPopUp("Disabled", selection: $format, options: [WindowPopUpOption(35, title: "35 mm")])
            .disabled(true)
    }
    .formStyle(.grouped)
    .frame(width: 320)
}
