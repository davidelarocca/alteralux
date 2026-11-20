import Foundation

// Undo and redo of the adjustments, as the toolbar and the tests ask for them. The Edit menu's
// own commands go straight to the window's undo manager, which is the same one.

extension AppModel {
    var canUndo: Bool {
        history.canUndo
    }

    var canRedo: Bool {
        history.canRedo
    }

    /// Takes back the last change of the adjustments: a whole drag, a film chosen, a reset.
    func undo() {
        history.undo()
    }

    func redo() {
        history.redo()
    }
}
