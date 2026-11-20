import AppKit
import SwiftUI

/// Holding M shows the original in place of the developed photo, and letting go brings the
/// developed photo back, as in Photos. A key typed in a text field is left to the field.
struct HoldToCompare: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var monitor: Any?
    /// Set while M is held and the original is shown because of it.
    @State private var isHolding = false

    /// The key held to compare.
    static let key = "m"

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { @MainActor event in
                    handle(event) ? nil : event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
                release()
            }
    }

    /// Whether `event` was the held key, taken here.
    private func handle(_ event: NSEvent) -> Bool {
        guard
            event.charactersIgnoringModifiers?.lowercased() == Self.key,
            event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
            let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
            !(window.firstResponder is NSText)
        else { return false }
        if event.type == .keyUp {
            guard isHolding else { return false }
            release()
            return true
        }
        if event.isARepeat {
            return isHolding
        }
        guard model.canCompare, !model.showsOriginal else { return false }
        isHolding = true
        model.showsOriginal = true
        return true
    }

    private func release() {
        guard isHolding else { return }
        isHolding = false
        model.showsOriginal = false
    }
}
