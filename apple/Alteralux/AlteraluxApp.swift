import AlteraluxUI
import AppIntents
import AppKit
import SwiftUI

/// The app: a thin shell around `AlteraluxUI`, which holds the screens and
/// the app model so they can be built and tested as a package.
@main
struct AlteraluxApp: App {
    /// Takes the files opened from the Finder, the Dock or `open`.
    @NSApplicationDelegateAdaptor(OpenFilesDelegate.self) private var openFiles
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        // The Shortcuts action develops photos with the same model as the window.
        AppDependencyManager.shared.add(dependency: model)
        // Always dark, like a darkroom: colors are judged against a neutral
        // dark interface, whatever the system appearance.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        Window("alteralux", id: MainWindow.id) {
            MainWindow()
                .environment(model)
                .onAppear { openFiles.attach(model) }
        }
        .defaultSize(MainWindow.defaultSize)
        .windowResizability(.contentMinSize)
        .commands {
            AlteraluxCommands(model: model)
        }

        Window("Recipes and Workflows", id: RecipesWindow.id) {
            RecipesWindow()
                .environment(model)
        }
        .defaultSize(RecipesWindow.defaultSize)
        .windowResizability(.contentMinSize)
    }
}
