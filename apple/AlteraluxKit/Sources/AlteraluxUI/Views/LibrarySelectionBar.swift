import DesignSystem
import SwiftUI

/// What can be done with the selected photos: give a recipe, export, move, copy, tag, discard.
/// It floats over the grid, near its bottom edge, while photos are selected.
///
/// Its lists open above it, inside the window: a menu would open downward, past the window's
/// edge. The bar never cuts a title short: where the grid is too narrow for every action side
/// by side, moving, copying and tagging show their symbols alone.
struct LibrarySelectionBar: View {
    @Environment(AppModel.self) private var model
    /// What was typed over the list of tags.
    @State private var typedTag = ""

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
        ChoiceListButton(Text("Recipe"), choices: recipes, empty: Text("No recipes yet. Save one while developing a photo."))
            .help("Give a recipe to the selected photos. Recipes are saved while developing a photo.")
        Button("Export…") { model.presentExport() }
            .help("Develop the selected photos and write them as files")
            .disabled(!model.canPresentExport)
        ChoiceListButton(
            Text("Move to…"), symbol: isCompact ? "folder" : nil,
            choices: destinations { folder in Task { await model.moveSelection(to: folder) } },
            empty: Text("No other folder in the library."),
        )
        .help("Move the selected photos to another folder of the library")
        ChoiceListButton(
            Text("Copy to…"), symbol: isCompact ? "plus.square.on.square" : nil,
            choices: destinations { folder in Task { await model.copySelection(to: folder) } },
            empty: Text("No other folder in the library."),
        )
        .help("Copy the selected photos to another folder of the library")
        ChoiceListButton(Text("Tag"), symbol: isCompact ? "tag" : nil, choices: tags, empty: noTag, staysOpen: true) {
            TagField(typed: $typedTag)
                .environment(model)
        }
        .help("Put a Finder tag on the selected photos, or take it off")
        Button("Discard") { model.discardSelection() }
            .help("Hide the selected photos. They stay on disk until the discarded photos are emptied.")
    }

    /// The recipes, each with its film and paper.
    private var recipes: [Choice] {
        model.recipes.map { recipe in
            Choice(id: recipe.id.uuidString, title: recipe.name, subtitle: model.materials(of: recipe.look)) {
                model.applyToSelection(recipe)
            }
        }
    }

    /// The Finder's tags with their colors: a check when every selected photo has the tag, a
    /// dash when some do.
    private var tags: [Choice] {
        let selected = model.library.selection.count
        return model.tagChoices.matching(typedTag).map { tag in
            // A tag without a color has the Finder's empty circle.
            Choice(
                id: tag.name, title: tag.name, color: tag.color?.swatch, symbol: "circle",
                mark: tag.carriedBy == 0 ? .off : tag.carriedBy == selected ? .all : .part,
            ) {
                model.toggleTag(tag.name, color: tag.color)
            }
        }
    }

    /// What the list of tags says when no tag's name holds what was typed.
    private var noTag: Text {
        let typed = typedTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Text("No Tags") : Text("Press Return to make the tag “\(typed)”.")
    }

    /// The folders of the library, the folder on screen left out.
    private func destinations(_ choose: @escaping (URL) -> Void) -> [Choice] {
        model.library.destinations.filter { $0.url != model.library.selectedFolder }.map { folder in
            Choice(id: folder.url.path, title: folder.name, symbol: "folder") { choose(folder.url) }
        }
    }
}
