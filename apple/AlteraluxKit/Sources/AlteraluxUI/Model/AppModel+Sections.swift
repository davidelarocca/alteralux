import AlteraluxKit
import Foundation

// The inspector's sections as parts of the adjustments (ADR 0016): whether one was changed, and
// putting one back as a new photo starts.

extension AppModel {
    /// Whether the controls of `part` differ from how a new photo starts.
    func isModified(_ part: DevelopPart) -> Bool {
        !settings.isAtStart(part)
    }

    /// Puts the controls of `part` back as a new photo starts, as one step of undo. The film,
    /// the paper and whether the film is scanned directly stay as they are.
    func reset(_ part: DevelopPart) {
        settings = settings.resetting(part)
    }

    /// The action that resets `part`, for a section's Reset button.
    func resetter(_ part: DevelopPart) -> () -> Void {
        { [weak self] in self?.reset(part) }
    }
}
