import DesignSystem
import SwiftUI

/// What can be done with the selected photos: move, copy, tag, give a recipe, export, discard.
///
/// The bar never cuts a title short. Where its column is too narrow for everything side by
/// side, clearing the selection becomes an icon, and then moving, copying and tagging go into
/// one menu.
struct LibrarySelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(isCompact: false, clearsWithIcon: false)
            row(isCompact: false, clearsWithIcon: true)
            row(isCompact: true, clearsWithIcon: true)
        }
        .menuStyle(.button)
        .controlSize(.small)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
    }

    private func row(isCompact: Bool, clearsWithIcon: Bool) -> some View {
        HStack(spacing: Spacing.m) {
            // Each control keeps the width of its title: the row says how wide it needs to be.
            Group {
                Text("\(model.library.selection.count) photos")
                    .font(Typography.value)
                if model.library.filter == .discarded {
                    Button("Take Back") { model.discardSelection() }
                        .help("Take the selected photos back among the others")
                } else {
                    actions(isCompact: isCompact)
                }
            }
            .fixedSize()
            Spacer(minLength: Spacing.s)
            Button {
                model.library.clearSelection()
            } label: {
                if clearsWithIcon {
                    Label("Clear Selection", systemImage: "xmark.circle").labelStyle(.iconOnly)
                } else {
                    Text("Clear Selection")
                }
            }
            .buttonStyle(.borderless)
            .help("Clear Selection")
            .fixedSize()
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func actions(isCompact: Bool) -> some View {
        if !isCompact {
            organizing
        }
        recipes
        Button("Export…") { model.presentExport() }
            .help("Develop the selected photos and write them as files")
            .disabled(!model.canPresentExport)
        Button("Discard") { model.discardSelection() }
            .help("Hide the selected photos. They stay on disk until the discarded photos are emptied.")
        if isCompact {
            Menu {
                organizing
            } label: {
                Label("More Actions", systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .help("Move, copy or tag the selected photos")
        }
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
