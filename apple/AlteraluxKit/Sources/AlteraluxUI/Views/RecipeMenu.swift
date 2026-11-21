import AlteraluxKit
import DesignSystem
import SwiftUI

/// The recipes as a menu, in the toolbar while developing: its button is the symbol alone, and
/// its menu opens inside the window (`WindowMenuButton`). Choosing a recipe gives it; under the
/// recipes the menu saves the look on screen as a new one, where there is one, asking for its
/// name with the system's alert, and opens the sheet that renames and deletes recipes. The menu
/// has no submenus: one would open past the window's edge.
struct RecipeMenu: View {
    let model: AppModel
    /// Whether there is a look on screen to save as a new recipe.
    let savesNew: Bool
    /// What choosing a recipe does: give it to the photo on screen, or to the selection.
    let give: (Recipe) -> Void

    @State private var isNaming = false
    @State private var isManaging = false
    @State private var name = ""

    var body: some View {
        WindowMenuButton(entries: entries) {
            Label("Recipe", systemImage: "camera.filters")
        }
        .alert("Save as New Recipe", isPresented: $isNaming) {
            TextField("Name", text: $name)
            Button("Save") {
                let name = name
                Task { await model.saveRecipe(named: name) }
            }
            .disabled(!AppModel.isRecipeName(name))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recipe keeps the look of this photo: everything but its white balance.")
        }
        .sheet(isPresented: $isManaging) {
            RecipeManager(model: model)
        }
    }

    /// The menu, made when it opens: the recipes, then saving one and managing them.
    private func entries() -> [WindowMenuEntry] {
        let recipes = model.recipes
        var entries: [WindowMenuEntry] = recipes.isEmpty
            ? [.note(String(localized: "No Recipes"))]
            : recipes.map { recipe in
                .item(recipe.name, subtitle: model.materials(of: recipe.look)) { give(recipe) }
            }
        entries.append(.separator)
        if savesNew {
            entries.append(.item(String(localized: "Save as New Recipe…")) {
                name = ""
                isNaming = true
            })
        }
        entries.append(.item(String(localized: "Manage Recipes…"), isEnabled: !recipes.isEmpty) {
            isManaging = true
        })
        return entries
    }
}

/// The recipes in a sheet, each with its film and paper, to rename or delete: the name is asked
/// for, and a deletion confirmed, with the system's alerts.
struct RecipeManager: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var question: RecipeQuestion?
    @State private var name = ""

    var body: some View {
        FormSheet(
            Text("Recipes"),
            message: Text("A recipe is a look saved under a name: everything but the white balance."),
            confirm: nil, cancel: SheetAction(Text("Done")) { dismiss() },
        ) {
            if model.recipes.isEmpty {
                Text("No Recipes")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.recipes) { recipe in
                LabeledContent {
                    HStack(spacing: Spacing.s) {
                        Button("Rename…") { ask(.rename, recipe) }
                        Button("Delete…", role: .destructive) { ask(.delete, recipe) }
                    }
                    .fixedSize()
                } label: {
                    Text(verbatim: recipe.name)
                    Text(verbatim: model.materials(of: recipe.look))
                }
                Toggle("Adapts to each photo", isOn: adapts(recipe))
                    .help("Each photo starts from its own exposure, and from an automatic white balance where the camera's is far off.")
            }
        }
        .alert("Rename Recipe", isPresented: isAsking(.rename)) {
            TextField("Name", text: $name)
            Button("Rename") { answer { recipe in await model.rename(recipe, to: name) } }
                .disabled(!AppModel.isRecipeName(name))
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete the recipe “\(question?.recipe?.name ?? "")”?", isPresented: isAsking(.delete),
        ) {
            Button("Delete", role: .destructive) { answer { recipe in await model.delete(recipe) } }
        } message: {
            Text("The photos that received it keep their adjustments.")
        }
    }

    /// Whether `recipe` adapts to each photo, saved as soon as it changes.
    private func adapts(_ recipe: Recipe) -> Binding<Bool> {
        Binding(
            get: { recipe.adaptsToEachPhoto },
            set: { adapts in Task { await model.setAdapts(recipe, adapts) } },
        )
    }

    private func ask(_ kind: RecipeQuestion.Kind, _ recipe: Recipe) {
        name = recipe.name
        question = RecipeQuestion(kind: kind, recipe: recipe)
    }

    private func isAsking(_ kind: RecipeQuestion.Kind) -> Binding<Bool> {
        Binding(
            get: { question?.kind == kind },
            set: {
                if !$0, question?.kind == kind {
                    question = nil
                }
            },
        )
    }

    /// Acts on the answer, with the recipe the question was about.
    private func answer(_ action: @escaping (Recipe) async -> Void) {
        guard let recipe = question?.recipe else { return }
        question = nil
        Task { await action(recipe) }
    }
}

/// What the recipe sheet asks the user, and about which recipe.
struct RecipeQuestion: Equatable {
    enum Kind {
        case rename, delete
    }

    let kind: Kind
    var recipe: Recipe?
}
