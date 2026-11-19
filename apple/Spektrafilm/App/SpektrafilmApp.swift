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
                    .disabled(!model.hasPhoto)
            }
            CommandGroup(before: .toolbar) {
                Toggle(
                    "Show Original",
                    isOn: Binding(
                        get: { model.showsOriginal },
                        set: { model.showsOriginal = $0 }))
                    .keyboardShortcut("\\", modifiers: [])
                    .disabled(model.original == nil)
                Divider()
                Button("Zoom to Fit") { model.zoom(.fit) }
                    .keyboardShortcut("9")
                Button("Actual Size") { model.zoom(.actualSize) }
                    .keyboardShortcut("0")
                Button("Zoom In") { model.zoom(.zoomIn) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { model.zoom(.zoomOut) }
                    .keyboardShortcut("-")
                Divider()
                Button("Previous Photo") { model.selectAdjacent(offset: -1) }
                    .keyboardShortcut(.leftArrow)
                Button("Next Photo") { model.selectAdjacent(offset: 1) }
                    .keyboardShortcut(.rightArrow)
                Divider()
            }
        }
    }
}
