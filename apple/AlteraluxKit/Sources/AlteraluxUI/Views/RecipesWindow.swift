import AlteraluxKit
import DesignSystem
import SwiftUI

/// The window of recipes: the recipes on the left, and on the right the one chosen, with its
/// look and the files it writes. Changing, duplicating and deleting a recipe are here; a recipe
/// is made from the look on screen, with the Recipe menu.
public struct RecipesWindow: View {
    /// The window's identifier, to open it.
    public static let id = "recipes"
    /// The smallest size the window can be resized to, in points.
    public static let minimumSize = CGSize(width: 640, height: 480)
    /// The size of a new window, in points.
    public static let defaultSize = CGSize(width: 780, height: 640)

    public init() {}

    public var body: some View {
        RecipesScreen()
            .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

/// The recipes and, for the one chosen, its look and its files.
struct RecipesScreen: View {
    @Environment(AppModel.self) private var model

    @State private var selection: Recipe.ID?
    /// The recipe being changed or duplicated in the editor.
    @State private var editing: RecipeDraft?
    /// The copy being made: chosen in the list once it is kept.
    @State private var copy: Recipe.ID?
    @State private var recipeToDelete: Recipe?

    var body: some View {
        NavigationSplitView {
            List(model.recipes, selection: $selection) { recipe in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: recipe.name)
                    Text(verbatim: model.materials(of: recipe.look))
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contextMenu {
                    Button("Edit…") { edit(recipe) }
                    Button("Duplicate…") { duplicate(recipe) }
                    Button("Delete…", role: .destructive) { recipeToDelete = recipe }
                }
            }
            .navigationSplitViewColumnWidth(
                min: SidebarWidth.minimum, ideal: SidebarWidth.ideal, max: SidebarWidth.maximum,
            )
        } detail: {
            if let recipe = chosen {
                RecipeDetail(
                    recipe: recipe, edit: { edit(recipe) }, duplicate: { duplicate(recipe) },
                    delete: { recipeToDelete = recipe },
                )
            } else {
                ContentUnavailableView(
                    "No Recipes",
                    systemImage: "camera.filters",
                    description: Text("Save the look of a photo as a recipe with the Recipe menu, while developing it."),
                )
            }
        }
        .navigationTitle("Recipes")
        .navigationSubtitle(chosen.map { Text(verbatim: $0.name) } ?? Text(verbatim: ""))
        .onChange(of: model.recipes, initial: true) {
            if let copy, model.recipes.contains(where: { $0.id == copy }) {
                selection = copy
                self.copy = nil
            } else if chosen == nil {
                selection = model.recipes.first?.id
            }
        }
        .sheet(item: $editing) { draft in
            RecipeEditor(draft: draft)
        }
        .confirmationDialog(
            "Delete the recipe “\(recipeToDelete?.name ?? "")”?", isPresented: isDeleting,
        ) {
            Button("Delete", role: .destructive) {
                guard let recipe = recipeToDelete else { return }
                recipeToDelete = nil
                Task { await model.delete(recipe) }
            }
        } message: {
            Text("The photos that received it keep their adjustments, and the files it wrote stay where they are.")
        }
    }

    /// The recipe chosen in the list, if it is still there.
    private var chosen: Recipe? {
        model.recipes.first { $0.id == selection }
    }

    private func edit(_ recipe: Recipe) {
        editing = RecipeDraft(recipe: recipe, kind: .edit)
    }

    /// Opens a copy of `recipe` in the editor: kept when it is saved there.
    private func duplicate(_ recipe: Recipe) {
        let draft = RecipeDraft(recipe: model.copy(of: recipe), kind: .duplicate)
        copy = draft.recipe.id
        editing = draft
    }

    private var isDeleting: Binding<Bool> {
        Binding(
            get: { recipeToDelete != nil },
            set: {
                if !$0 {
                    recipeToDelete = nil
                }
            },
        )
    }
}

/// One recipe: its film and paper, where it starts each photo from, and the files it writes.
struct RecipeDetail: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Film and paper") {
                    Text(verbatim: model.materials(of: recipe.look))
                }
                RecipeLightRows(recipe: recipe)
            } footer: {
                note(
                    "A recipe is the look of a photo saved under a name, without its white balance. What was saved on Auto is found again in each photo.",
                )
            }
            Section {
                LabeledContent("Files") {
                    Text(verbatim: AppModel.summary(of: recipe.files))
                }
            } footer: {
                note(
                    "Developing photos with the recipe writes these files and leaves their adjustments alone. For other files, duplicate the recipe.",
                )
            }
            Section {
                HStack(spacing: Spacing.s) {
                    Button("Edit…", action: edit)
                    Button("Duplicate…", action: duplicate)
                    Button("Delete…", role: .destructive, action: delete)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
