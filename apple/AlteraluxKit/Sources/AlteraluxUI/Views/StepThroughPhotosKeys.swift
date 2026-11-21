import SwiftUI

/// The left and right arrows go to the previous and the next photo, as in a photo viewer.
///
/// The app's menu has these shortcuts too, but macOS gives a menu no arrow key pressed alone:
/// the view on screen takes them. It takes the keys when it appears and when it is clicked; a
/// control that takes the keys after it (a slider of the adjustments) keeps its arrows until
/// the photo is clicked again.
struct StepThroughPhotosKeys: ViewModifier {
    /// Goes `offset` photos further, and says whether it could.
    let step: (_ offset: Int) -> Bool
    @FocusState private var hasKeys: Bool

    /// Whether the arrow was pressed with no modifier key. An arrow always counts as a key of
    /// the numeric keypad, so that one is left out.
    private static func isAlone(_ press: KeyPress) -> Bool {
        press.modifiers.isDisjoint(with: [.command, .option, .control, .shift])
    }

    func body(content: Content) -> some View {
        content
            // As the sliders: the system gives plain focus only with "Keyboard navigation" on.
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($hasKeys)
            .onKeyPress(.leftArrow, phases: [.down, .repeat]) { press in
                Self.isAlone(press) && step(-1) ? .handled : .ignored
            }
            .onKeyPress(.rightArrow, phases: [.down, .repeat]) { press in
                Self.isAlone(press) && step(1) ? .handled : .ignored
            }
            .simultaneousGesture(TapGesture().onEnded { hasKeys = true })
            .onAppear { hasKeys = true }
    }
}
