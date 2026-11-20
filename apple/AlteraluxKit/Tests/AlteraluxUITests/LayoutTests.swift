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
}
