import SwiftUI

/// The app's menu commands: File (Open, Export), Edit (Reset, copy and paste adjustments), View (compare,
/// zoom, previous and next photo), About and Help.
public struct AlteraluxCommands: Commands {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About alteralux") { AboutPanel.show() }
        }
        CommandGroup(replacing: .help) {
            Link("alteralux for macOS on GitHub", destination: AboutPanel.repositoryURL)
            Link("The Original spektrafilm Project", destination: AboutPanel.upstreamURL)
        }
        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.isImporterPresented = true }
                .keyboardShortcut("o")
            Button("Add Folder to Library…") { model.chooseFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .importExport) {
            Button("Export…") { model.presentExport() }
                .keyboardShortcut("e")
                .disabled(!model.canPresentExport)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Adjustments") { model.copyAdjustments() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canCopyAdjustments)
            Button("Paste Adjustments") { model.pasteAdjustments() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!model.canPasteAdjustments)
        }
        CommandGroup(after: .undoRedo) {
            Button("Reset Adjustments") { model.resetAdjustments() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.hasPhoto)
        }
        CommandGroup(before: .toolbar) {
            Button("Library") { model.showLibrary() }
                .keyboardShortcut("l")
                .disabled(!model.hasLibrary || model.showsLibrary)
            Divider()
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
