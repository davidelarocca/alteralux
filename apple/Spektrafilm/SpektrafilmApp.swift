import AppKit
import SpektrafilmUI
import SwiftUI

/// The app: a thin shell around `SpektrafilmUI`, which holds the screens and
/// the app model so they can be built and tested as a package.
@main
struct SpektrafilmApp: App {
    @State private var model = AppModel()

    init() {
        // Always dark, like a darkroom: colors are judged against a neutral
        // dark interface, whatever the system appearance.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        Window("spektrafilm", id: "main") {
            MainWindow()
                .environment(model)
        }
        .defaultSize(MainWindow.defaultSize)
        .windowResizability(.contentMinSize)
        .commands {
            SpektrafilmCommands(model: model)
        }
    }
}
