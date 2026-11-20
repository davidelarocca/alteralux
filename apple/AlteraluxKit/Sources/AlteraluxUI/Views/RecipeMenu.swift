import AlteraluxKit
import SwiftUI

/// The recipes as a menu, the same wherever recipes are given: in the toolbar while developing
/// and in the bar of the library's selection. Choosing a recipe gives it; under the recipes the
/// menu saves the look on screen as a new one, where there is one, and renames or deletes a
/// recipe, asking for the name or for a confirmation with the system's alerts.
struct RecipeMenu: View {
    let model: AppModel
    /// Whether there is a look on screen to save as a new recipe.
    let savesNew: Bool
    /// What choosing a recipe does: give it to the photo on screen, or to the selection.
    let give: (Recipe) -> Void

    @State private var question: RecipeQuestion?
    @State private var name = ""

    var body: some View {
        Menu {
            if model.recipes.isEmpty {
                Text("No Recipes")
            }
            ForEach(model.recipes) { recipe in
                Button {
                    give(recipe)
                } label: {
                    Text(verbatim: recipe.name)
                    Text(verbatim: model.materials(of: recipe.look))
                }
            }
            Divider()
            if savesNew {
                Button("Save as New Recipe…") { ask(.new) }
            }
            Menu("Rename") {
                ForEach(model.recipes) { recipe in
                    Button { ask(.rename, recipe) } label: { Text(verbatim: recipe.name) }
                }
            }
            .disabled(model.recipes.isEmpty)
            Menu("Delete") {
                ForEach(model.recipes) { recipe in
                    Button { ask(.delete, recipe) } label: { Text(verbatim: recipe.name) }
                }
            }
            .disabled(model.recipes.isEmpty)
        } label: {
            Label("Recipe", systemImage: "camera.filters")
        }
        .alert("Save as New Recipe", isPresented: isAsking(.new)) {
            TextField("Name", text: $name)
            Button("Save") { answer { _ in await model.saveRecipe(named: name) } }
                .disabled(!AppModel.isRecipeName(name))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recipe keeps the look of this photo: everything but its white balance.")
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

    private func ask(_ kind: RecipeQuestion.Kind, _ recipe: Recipe? = nil) {
        name = recipe?.name ?? ""
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

    /// Acts on the answer: with the recipe the question was about, or with a blank one for a
    /// question about a new recipe, which does not look at it.
    private func answer(_ action: @escaping (Recipe) async -> Void) {
        let recipe = question?.recipe ?? Recipe(name: "", from: DevelopSettings())
        question = nil
        Task { await action(recipe) }
    }
}

/// What the recipe menu asks the user, and about which recipe.
struct RecipeQuestion: Equatable {
    enum Kind {
        case new, rename, delete
    }

    let kind: Kind
    /// The recipe to rename or delete; `nil` for a new one.
    var recipe: Recipe?
}
