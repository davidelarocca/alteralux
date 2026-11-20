import SwiftUI

/// The app's menu commands: File (Open, Export), Edit (Reset, copy and paste adjustments), View (compare,
/// zoom, previous and next photo), About and Help.
public struct AlteraluxCommands: Commands {
    private let model: AppModel
    /// The size of the library's thumbnails, which Zoom In and Zoom Out change in the library.
    @AppStorage(LibraryGrid.thumbnailSizeKey) private var thumbnailSize = LibraryGrid.defaultThumbnailSize
    /// Whether the strip of photos shows under the photo being developed.
    @AppStorage(DevelopScreen.showsStripKey) private var showsStrip = true

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
            Button("Crop and Straighten") { model.beginCrop() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!model.canCrop || model.isCropping)
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
            .disabled(model.original == nil || model.showsLibrary)
            Toggle("Show Strip", isOn: $showsStrip)
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.showsLibrary)
            Divider()
            Group {
                Button("Zoom to Fit") { model.zoom(.fit) }
                    .keyboardShortcut("9")
                Button("Actual Size") { model.zoom(.actualSize) }
                    .keyboardShortcut("0")
            }
            .disabled(!model.canZoom || model.showsLibrary)
            // In the library they make the thumbnails larger or smaller, as in the Finder.
            Button("Zoom In") { model.showsLibrary ? resizeThumbnails(by: 1) : model.zoom(.zoomIn) }
                .keyboardShortcut("+")
                .disabled(model.showsLibrary ? thumbnailSize >= LibraryGrid.thumbnailSizes.upperBound : !model.canZoom)
            Button("Zoom Out") { model.showsLibrary ? resizeThumbnails(by: -1) : model.zoom(.zoomOut) }
                .keyboardShortcut("-")
                .disabled(model.showsLibrary ? thumbnailSize <= LibraryGrid.thumbnailSizes.lowerBound : !model.canZoom)
            Divider()
            Group {
                Button("Previous Photo") { model.selectAdjacent(offset: -1) }
                    .keyboardShortcut(.leftArrow)
                Button("Next Photo") { model.selectAdjacent(offset: 1) }
                    .keyboardShortcut(.rightArrow)
            }
            .disabled(!model.canStepThroughPhotos || model.showsLibrary)
            Button("Remove from Strip") { model.removeSelection() }
                .keyboardShortcut(.delete)
                .disabled(!model.hasPhoto || model.showsLibrary)
            Divider()
        }
    }

    /// Makes the library's thumbnails a step larger or smaller.
    private func resizeThumbnails(by steps: Double) {
        let size = thumbnailSize + steps * LibraryGrid.thumbnailSizeStep
        thumbnailSize = min(max(size, LibraryGrid.thumbnailSizes.lowerBound), LibraryGrid.thumbnailSizes.upperBound)
    }
}
