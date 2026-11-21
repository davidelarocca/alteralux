import AppKit

/// The list of workflows that opens beside the pointer for photos sent from the Finder's
/// "Develop with alteralux…": one click develops them. A system menu, like the Finder's own
/// right-click menu it follows.
@MainActor
enum WorkflowChoiceMenu {
    /// Shows the workflows by name, each with what it writes, and returns the one chosen, or
    /// `nil` when the menu is left.
    static func choose(from workflows: [WorkflowChoice], photos: Int) -> WorkflowChoice.ID? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: String(localized: "Develop \(photos) Photos with")))
        let picker = Picker()
        for (index, workflow) in workflows.enumerated() {
            let item = NSMenuItem(title: workflow.name, action: #selector(Picker.pick(_:)), keyEquivalent: "")
            item.subtitle = workflow.summary
            item.target = picker
            item.tag = index
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return picker.chosen.map { workflows[$0].id }
    }

    /// Takes note of the item chosen.
    private final class Picker: NSObject {
        var chosen: Int?

        @objc func pick(_ item: NSMenuItem) {
            chosen = item.tag
        }
    }
}
