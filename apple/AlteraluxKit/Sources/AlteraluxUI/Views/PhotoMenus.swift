import AppKit
import SwiftUI

/// The menu of a photo of the library's grid, opened with a secondary click: what the bar of
/// the selection offers, with Develop and Show in Finder. As in the Finder, a photo clicked
/// outside the selection becomes the selection when one of its actions is taken.
struct LibraryPhotoMenu: View {
    @Environment(AppModel.self) private var model
    let photo: URL

    var body: some View {
        let library = model.library
        Button("Develop") { model.develop(photo) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets) }
        Divider()
        Menu("Recipe") {
            ForEach(model.recipes) { recipe in
                Button(recipe.name) { act { model.applyToSelection(recipe) } }
            }
        }
        .disabled(model.recipes.isEmpty)
        Button("Export…") { act { model.presentExport() } }
        Menu("Move to") {
            ForEach(destinations, id: \.url) { folder in
                Button(folder.name) { act { Task { await model.moveSelection(to: folder.url) } } }
            }
        }
        .disabled(destinations.isEmpty)
        Menu("Copy to") {
            ForEach(destinations, id: \.url) { folder in
                Button(folder.name) { act { Task { await model.copySelection(to: folder.url) } } }
            }
        }
        .disabled(destinations.isEmpty)
        Divider()
        Button("Copy Adjustments") { act { model.copyAdjustments() } }
            .disabled(targets.count != 1)
        Button("Paste Adjustments") { act { model.pasteAdjustments() } }
            .disabled(model.copiedAdjustments == nil)
        Divider()
        Button(library.filter == .discarded ? "Take Back" : "Discard") { act { model.discardSelection() } }
    }

    /// The photos an action goes to: the selection when the photo is in it, the photo alone
    /// otherwise.
    private var targets: [URL] {
        model.library.selection.contains(photo) ? model.selectedPhotos : [photo]
    }

    /// The folders of the library a photo can go to, the folder on screen left out.
    private var destinations: [(url: URL, name: String)] {
        model.library.destinations.filter { $0.url != model.library.selectedFolder }.map { ($0.url, $0.name) }
    }

    /// Makes the photo the selection when it is not in it, then acts on the selection.
    private func act(_ action: () -> Void) {
        if !model.library.selection.contains(photo) {
            model.library.click(photo)
        }
        action()
    }
}

/// The menu of the photo being developed, opened with a secondary click: its adjustments,
/// the comparison with the original, and the file.
struct DevelopPhotoMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle("Show Original", isOn: $model.showsOriginal)
            .disabled(model.original == nil)
        Divider()
        Button("Copy Adjustments") { model.copyAdjustments() }
            .disabled(!model.canCopyAdjustments)
        Button("Paste Adjustments") { model.pasteAdjustments() }
            .disabled(!model.canPasteAdjustments)
        Button("Reset Adjustments") { model.resetAdjustments() }
            .disabled(!model.hasPhoto)
        Button("Crop and Straighten") { model.beginCrop() }
            .disabled(!model.canCrop || model.isCropping)
        Divider()
        Button("Export…") { model.presentExport() }
            .disabled(!model.canPresentExport)
        if let photo = model.selection?.url {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([photo]) }
        }
    }
}
