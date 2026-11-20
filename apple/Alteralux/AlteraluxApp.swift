import AlteraluxUI
import AppKit
import SwiftUI

/// The app: a thin shell around `AlteraluxUI`, which holds the screens and
/// the app model so they can be built and tested as a package.
@main
struct AlteraluxApp: App {
    /// Takes the files opened from the Finder, the Dock or `open`.
    @NSApplicationDelegateAdaptor(OpenFilesDelegate.self) private var openFiles
    @State private var model = AppModel()

    init() {
        // Always dark, like a darkroom: colors are judged against a neutral
        // dark interface, whatever the system appearance.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        Window("alteralux", id: "main") {
            MainWindow()
                .environment(model)
                .onAppear { openFiles.attach(model) }
        }
        .defaultSize(MainWindow.defaultSize)
        .windowResizability(.contentMinSize)
        .commands {
            AlteraluxCommands(model: model)
        }
    }
}
