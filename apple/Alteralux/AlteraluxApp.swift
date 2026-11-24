import AlteraluxUI
import AppKit
import SwiftUI

/// The app: a thin shell around `AlteraluxUI`, which holds the screens and
/// the app model so they can be built and tested as a package.
@main
struct AlteraluxApp: App {
    /// Takes what the system hands to the app, and holds the app's model from launch: the Finder
    /// can start the app to develop photos without any window.
    @NSApplicationDelegateAdaptor(OpenFilesDelegate.self) private var app

    init() {
        // Always dark, like a darkroom: colors are judged against a neutral
        // dark interface, whatever the system appearance.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        // Opened by the app delegate when the app is opened, not when the Finder starts it.
        Window("alteralux", id: MainWindow.id) {
            MainWindow()
                .environment(app.model)
        }
        .defaultSize(MainWindow.defaultSize)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            AlteraluxCommands(model: app.model)
        }

        Window("Recipes", id: RecipesWindow.id) {
            RecipesWindow()
                .environment(app.model)
        }
        .defaultSize(RecipesWindow.defaultSize)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
