import AlteraluxKit
import DesignSystem
import SwiftUI

/// The recipes as a menu, in the toolbar while developing: its button is the symbol alone, and
/// its menu opens inside the window (`WindowMenuButton`). Choosing a recipe gives it; under the
/// recipes the menu saves the look on screen as a new one, where there is one, in a sheet that
/// asks its name and shows the files it writes, and opens the window of recipes. The menu has no
/// submenus: one would open past the window's edge.
struct RecipeMenu: View {
    let model: AppModel
    /// Whether there is a look on screen to save as a new recipe.
    let savesNew: Bool
    /// What choosing a recipe does: give it to the photo on screen, or to the selection.
    let give: (Recipe) -> Void

    @Environment(\.openWindow) private var openWindow
    /// The recipe being saved, in its sheet.
    @State private var saving: RecipeDraft?

    var body: some View {
        WindowMenuButton(entries: entries) {
            Label("Recipe", systemImage: "camera.filters")
        }
        .sheet(item: $saving) { draft in
            RecipeEditor(draft: draft)
                .environment(model)
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
                saving = RecipeDraft(recipe: model.newRecipe(), kind: .new)
            })
        }
        entries.append(.item(String(localized: "Manage Recipes…")) {
            openWindow(id: RecipesWindow.id)
        })
        return entries
    }
}
