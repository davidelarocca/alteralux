import AppKit
import Testing
@testable import DesignSystem

/// The toolbar's menus open inside the window, whatever the side of the button.
struct WindowMenuTests {
    private let margin = Spacing.s

    @Test func aMenuNearTheTrailingEdgeMovesInside() {
        // A 300 pt menu under a button 100 pt from the edge of a 1240 pt window.
        let leading = WindowMenu.leadingEdge(of: 300, under: 1140, in: 1240)
        #expect(leading + 300 <= 1240 - margin + 1e-9)
    }

    @Test func aMenuWithRoomIsCenteredUnderTheClick() {
        #expect(WindowMenu.leadingEdge(of: 200, under: 600, in: 1240) == 500)
    }

    @Test func aMenuNearTheLeadingEdgeMovesInside() {
        #expect(WindowMenu.leadingEdge(of: 300, under: 20, in: 1240) == margin)
    }

    @Test @MainActor func theEntriesBecomeTheSystemsMenu() {
        var chosen = false
        let menu = WindowMenu.makeMenu([
            .item("One", subtitle: "Context") { chosen = true },
            .separator,
            .note("Nothing"),
            .submenu("More", isEnabled: false, entries: [.item("Two") {}]),
        ])
        #expect(menu.items.map(\.title) == ["One", "", "Nothing", "More"])
        #expect(menu.items[0].subtitle == "Context" && menu.items[1].isSeparatorItem)
        #expect(!menu.items[2].isEnabled && !menu.items[3].isEnabled && menu.items[3].submenu?.items.count == 1)
        // What the system does when the item is chosen: its action, sent to its target.
        let item = menu.items[0]
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
        #expect(chosen)
    }
}
