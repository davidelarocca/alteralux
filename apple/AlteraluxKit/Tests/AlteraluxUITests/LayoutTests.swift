import Foundation
import SwiftUI
import Testing
@testable import AlteraluxUI

/// Measures the screens of docs/LAYOUT_CONTRACT.md at the sizes their rows declare.
@MainActor
struct LayoutTests {
    @Test func mainWindowDeclaresItsMinimumSize() {
        #expect(LayoutContract.check("MainWindow") { MainWindow().environment(AppModel()) } == [])
    }

    @Test func theLibrarysFoldersFitTheirColumn() {
        #expect(LayoutContract.check("LibrarySidebar") {
            LibrarySidebar(isAddingFolder: .constant(false)).environment(AppModel())
        } == [])
    }

    @Test func theLibrarysPhotosFitTheirColumn() {
        #expect(LayoutContract.check("LibraryGrid") {
            LibraryGrid(isAddingFolder: .constant(false)).environment(AppModel())
        } == [])
    }

    /// With photos selected the grid has their bar under it, its widest row.
    @Test func theLibrarysPhotosFitTheirColumnWithASelection() {
        let model = AppModel()
        model.library.selection = [URL(fileURLWithPath: "/photos/a.jpg"), URL(fileURLWithPath: "/photos/b.jpg")]
        #expect(LayoutContract.check("LibraryGrid") {
            LibraryGrid(isAddingFolder: .constant(false)).environment(model)
        } == [])
    }
}
