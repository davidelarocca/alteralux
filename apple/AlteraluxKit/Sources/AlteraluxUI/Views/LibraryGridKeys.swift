import SwiftUI

/// The keys of the library's grid, as in the Finder: the arrows move through the photos and,
/// with Shift, grow the selection; Home and End go to the first and the last photo, Page Up and
/// Page Down a screen at a time; Space opens Quick Look; Return develops; Delete discards;
/// Escape clears the selection; Command-A selects every photo shown.
struct LibraryGridKeys: ViewModifier {
    @Environment(AppModel.self) private var model
    /// The grid's rows, for the photo above or below.
    let rows: LibraryRows
    /// How many rows a screen of the grid holds, for Page Up and Page Down.
    let pageRows: Int
    /// Brings a photo the keys reached in sight.
    let reveal: (URL?) -> Void
    /// The photo Quick Look shows, while it is open.
    @Binding var quickLook: URL?

    func body(content: Content) -> some View {
        let library = model.library
        content
            .onKeyPress(.leftArrow, phases: [.down, .repeat]) { press in step(by: -1, press) }
            .onKeyPress(.rightArrow, phases: [.down, .repeat]) { press in step(by: 1, press) }
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in move(rowsDown: -1, press) }
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in move(rowsDown: 1, press) }
            .onKeyPress(.pageUp, phases: [.down, .repeat]) { press in move(rowsDown: -pageRows, press) }
            .onKeyPress(.pageDown, phases: [.down, .repeat]) { press in move(rowsDown: pageRows, press) }
            .onKeyPress(.home, phases: [.down, .repeat]) { press in step(by: -library.visiblePhotos.count, press) }
            .onKeyPress(.end, phases: [.down, .repeat]) { press in step(by: library.visiblePhotos.count, press) }
            .onKeyPress(.space) {
                quickLook = quickLook == nil ? library.focusedPhoto : nil
                return quickLook == nil && library.focusedPhoto == nil ? .ignored : .handled
            }
            .onKeyPress(.return) {
                guard let photo = library.focusedPhoto else { return .ignored }
                model.develop(photo)
                return .handled
            }
            .onKeyPress(.escape) {
                library.clearSelection()
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{7F}")]) { _ in
                guard !library.selection.isEmpty else { return .ignored }
                model.discardSelection()
                return .handled
            }
            .onKeyPress(keys: ["a"]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                library.selectAll()
                return .handled
            }
    }

    /// Goes to the photo `offset` places before or after the one the keys are on.
    private func step(by offset: Int, _ press: KeyPress) -> KeyPress.Result {
        let library = model.library
        library.moveSelection(by: offset, extending: press.modifiers.contains(.shift))
        reveal(library.focusedPhoto)
        return .handled
    }

    /// Goes to the photo some rows above or below the one the keys are on, or to the first
    /// photo when none is selected yet.
    private func move(rowsDown: Int, _ press: KeyPress) -> KeyPress.Result {
        let library = model.library
        if let photo = library.focusedPhoto {
            // A page past the first or the last row stops there.
            let row = rows.rows.firstIndex { $0.items.contains { $0.photo == photo } }
            let rowsDown = row.map { min(max($0 + rowsDown, 0), rows.rows.count - 1) - $0 } ?? rowsDown
            if let target = rows.photo(from: photo, rowsDown: rowsDown) {
                library.click(target, extending: press.modifiers.contains(.shift))
            }
        } else {
            library.moveSelection(by: rowsDown.signum())
        }
        reveal(library.focusedPhoto)
        return .handled
    }
}
