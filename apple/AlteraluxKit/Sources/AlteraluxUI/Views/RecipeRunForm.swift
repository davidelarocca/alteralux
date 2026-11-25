import AlteraluxKit
import DesignSystem
import SwiftUI

/// The export sheet's form for developing the selected photos of the library with a recipe:
/// which recipe, and the settings it leaves open.
struct RecipeRunForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The recipe chosen, with the answers to what it asks; at first the one chosen last.
    @State private var answered: Recipe?

    var body: some View {
        let run = answered ?? model.chosenRecipe
        FormSheet(
            Text("Develop \(model.photosToExport.count) Photos"),
            message: Text("Each photo is written as a file with the recipe’s look, and keeps its own adjustments."),
            confirm: SheetAction(Text("Develop"), isEnabled: run.map { AppModel.canWrite($0.files) } ?? false) {
                Task { await model.developWithRecipe(run) }
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            if let run {
                RecipeRunSection(recipes: model.recipes, run: Binding(get: { answered ?? run }, set: { answered = $0 }))
            }
        }
    }
}
