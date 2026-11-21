import AlteraluxKit
import Foundation
import SwiftUI
import Testing
@testable import AlteraluxUI

/// Measures the screens of docs/LAYOUT_CONTRACT.md at the sizes their rows declare.
@MainActor
struct LayoutTests {
    @Test func mainWindowDeclaresItsMinimumSize() {
        #expect(LayoutContract.check("MainWindow") { MainWindow().environment(AppModel()) } == [])
    }

    @Test func theLibrarysFoldersFitTheirColumn() {
        #expect(LayoutContract.check("LibrarySidebar") {
            LibrarySidebar(isAddingFolder: .constant(false)).environment(AppModel())
        } == [])
    }

    @Test func theLibrarysPhotosFitTheirColumn() {
        #expect(LayoutContract.check("LibraryGrid") {
            LibraryGrid(isAddingFolder: .constant(false)).environment(AppModel())
        } == [])
    }

    /// With photos selected the grid has their bar under it, its widest row.
    @Test func theLibrarysPhotosFitTheirColumnWithASelection() {
        let model = AppModel()
        model.library.selection = [URL(fileURLWithPath: "/photos/a.jpg"), URL(fileURLWithPath: "/photos/b.jpg")]
        #expect(LayoutContract.check("LibraryGrid") {
            LibraryGrid(isAddingFolder: .constant(false)).environment(model)
        } == [])
    }

    @Test func theRecipesWindowDeclaresItsMinimumSize() {
        #expect(LayoutContract.check("RecipesWindow") { RecipesWindow().environment(AppModel()) } == [])
    }

    /// A recipe with two workflows, one of them with a long name, at the width the detail
    /// column has beside the list of recipes.
    @Test func aRecipeAndItsWorkflowsFitTheirColumn() {
        let model = AppModel()
        let recipe = Recipe(name: "Evening slide with a long name", from: DevelopSettings())
        model.recipes = [recipe]
        model.workflows = [
            Workflow(name: "Web", recipeID: recipe.id, options: ExportOptions(longSide: 2048), destination: .besideOriginals(folderName: "Web")),
            Workflow(name: "Prints for the exhibition in the autumn", recipeID: recipe.id, destination: .besideOriginals(folderName: "Developed")),
        ]
        #expect(LayoutContract.check("RecipeDetail") {
            RecipeDetail(recipe: recipe, rename: {}, delete: {}).environment(model)
        } == [])
    }
}
