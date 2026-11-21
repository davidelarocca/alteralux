import AlteraluxKit
import DesignSystem
import SwiftUI

/// The recipes as a menu, in the toolbar while developing: its button is the symbol alone, and
/// its menu opens inside the window (`WindowMenuButton`). Choosing a recipe gives it; under the
/// recipes the menu saves the look on screen as a new one, where there is one, asking for its
/// name with the system's alert, and opens the window of recipes and workflows. The menu has no
/// submenus: one would open past the window's edge.
struct RecipeMenu: View {
    let model: AppModel
    /// Whether there is a look on screen to save as a new recipe.
    let savesNew: Bool
    /// What choosing a recipe does: give it to the photo on screen, or to the selection.
    let give: (Recipe) -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var isNaming = false
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
        entries.append(.item(String(localized: "Recipes and Workflows…")) {
            openWindow(id: RecipesWindow.id)
        })
        return entries
    }
}

/// What the recipe window asks the user, and about which recipe.
struct RecipeQuestion: Equatable {
    enum Kind {
        case rename, delete
    }

    let kind: Kind
    var recipe: Recipe?
}
