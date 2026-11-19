import SwiftUI

/// The app's menu commands: File (Open, Export), Edit (Reset), View (compare,
/// zoom, previous and next photo), About and Help.
public struct SpektrafilmCommands: Commands {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About spektrafilm") { AboutPanel.show() }
        }
        CommandGroup(replacing: .help) {
            Link("spektrafilm for macOS on GitHub", destination: AboutPanel.repositoryURL)
            Link("The Original spektrafilm Project", destination: AboutPanel.upstreamURL)
        }
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
                    set: { model.showsOriginal = $0 },
                ),
            )
            .keyboardShortcut("\\", modifiers: [])
            .disabled(model.original == nil)
            Divider()
            Group {
                Button("Zoom to Fit") { model.zoom(.fit) }
                    .keyboardShortcut("9")
                Button("Actual Size") { model.zoom(.actualSize) }
                    .keyboardShortcut("0")
                Button("Zoom In") { model.zoom(.zoomIn) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { model.zoom(.zoomOut) }
                    .keyboardShortcut("-")
            }
            .disabled(!model.canZoom)
            Divider()
            Group {
                Button("Previous Photo") { model.selectAdjacent(offset: -1) }
                    .keyboardShortcut(.leftArrow)
                Button("Next Photo") { model.selectAdjacent(offset: 1) }
                    .keyboardShortcut(.rightArrow)
            }
            .disabled(!model.canStepThroughPhotos)
            Button("Remove from Strip") { model.removeSelection() }
                .keyboardShortcut(.delete)
                .disabled(!model.hasPhoto)
            Divider()
        }
    }
}
