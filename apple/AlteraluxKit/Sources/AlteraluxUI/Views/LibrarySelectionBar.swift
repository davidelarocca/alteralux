import DesignSystem
import SwiftUI

/// What can be done with the selected photos: give a recipe, export, move, copy, tag, discard.
/// It floats over the grid, near its bottom edge, while photos are selected.
///
/// The bar never cuts a title short. Where the grid is too narrow for every action side by
/// side, moving, copying and tagging go into one menu.
struct LibrarySelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(isCompact: false)
            bar(isCompact: true)
        }
    }

    private func bar(isCompact: Bool) -> some View {
        FloatingBar {
            Text("\(model.library.selection.count) photos")
                .font(Typography.value)
            Divider()
            if model.library.filter == .discarded {
                Button("Take Back") { model.discardSelection() }
                    .help("Take the selected photos back among the others")
            } else {
                actions(isCompact: isCompact)
            }
            Divider()
            Button {
                model.library.clearSelection()
            } label: {
                Label("Clear Selection", systemImage: "xmark").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Clear Selection")
        }
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder
    private func actions(isCompact: Bool) -> some View {
        recipes
        Button("Export…") { model.presentExport() }
            .help("Develop the selected photos and write them as files")
            .disabled(!model.canPresentExport)
        if isCompact {
            Menu {
                organizing
            } label: {
                Label("More Actions", systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .help("Move, copy or tag the selected photos")
        } else {
            organizing
        }
        Button("Discard") { model.discardSelection() }
            .help("Hide the selected photos. They stay on disk until the discarded photos are emptied.")
    }

    /// Moving, copying and tagging: three menus side by side, or the entries of one.
    @ViewBuilder private var organizing: some View {
        Menu("Move to…") {
            destinations { folder in Task { await model.moveSelection(to: folder) } }
        }
        .help("Move the selected photos to another folder of the library")
        Menu("Copy to…") {
            destinations { folder in Task { await model.copySelection(to: folder) } }
        }
        .help("Copy the selected photos to another folder of the library")
        Menu("Tag") {
            ForEach(model.tagChoices, id: \.name) { choice in
                Button {
                    model.toggleTag(choice.name)
                } label: {
                    // A check when every selected photo has the tag, a dash when some do.
                    if choice.carriedBy > 0 {
                        Label {
                            Text(verbatim: choice.name)
                        } icon: {
                            Image(systemName: choice.carriedBy == model.library.selection.count ? "checkmark" : "minus")
                        }
                    } else {
                        Text(verbatim: choice.name)
                    }
                }
            }
        }
        .help("Put a Finder tag on the selected photos, or take it off")
    }

    private var recipes: some View {
        RecipeMenu(model: model, savesNew: false) { model.applyToSelection($0) }
            .labelStyle(.titleOnly)
            .help("Give a recipe to the selected photos. Recipes are saved while developing a photo.")
    }

    /// The folders of the library as menu items, the folder on screen left out.
    private func destinations(_ choose: @escaping (URL) -> Void) -> some View {
        ForEach(model.library.destinations.filter { $0.url != model.library.selectedFolder }) { folder in
            Button {
                choose(folder.url)
            } label: {
                Label(folder.name, systemImage: "folder")
            }
        }
    }
}
