import SwiftUI

@main
struct SpektrafilmApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("spektrafilm", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .importExport) {
                Button("Export…") { model.isExportPresented = true }
                    .keyboardShortcut("e")
                    .disabled(!model.canExport)
            }
            CommandGroup(after: .undoRedo) {
                Button("Reset Adjustments") { model.resetAdjustments() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.photo == nil)
            }
        }
    }
}
