import SwiftUI
import Testing
@testable import SpektrafilmUI

/// Measures the screens of docs/LAYOUT_CONTRACT.md at the sizes their rows declare.
@MainActor
struct LayoutTests {
    @Test func mainWindowDeclaresItsMinimumSize() {
        #expect(LayoutContract.check("MainWindow") { MainWindow().environment(AppModel()) } == [])
    }
}
