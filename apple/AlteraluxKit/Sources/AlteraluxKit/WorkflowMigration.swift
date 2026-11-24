import Foundation

/// Turns the workflows the app kept before recipes wrote files (ADR 0013, ADR 0014) into
/// recipes, once (ADR 0021).
///
/// A workflow was a way of using a recipe, named by id: whether it adapted to each photo, and
/// the files it wrote. Each one becomes a recipe with the look of its recipe and its own name,
/// files and id, so a shortcut that chose the workflow chooses the recipe. One that adapted has
/// the automatic exposure and the automatic white balance. A workflow with the name of its
/// recipe takes the recipe's place; another one stands beside it.
public enum WorkflowMigration {
    /// Makes recipes in `store` of the workflow files in `directory`, and removes the files. A
    /// workflow whose recipe is gone is removed: it developed nothing. One that cannot be read
    /// or kept as a recipe is left where it is.
    public static func run(workflows directory: URL, into store: RecipeStore) async {
        let manager = FileManager.default
        let files = ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "json" }
        guard !files.isEmpty else { return }
        let recipes = await store.all()
        var replaced: Set<Recipe.ID> = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let workflow = (try? JSONDecoder().decode(Stored.self, from: data))?.workflow else { continue }
            if let recipe = recipes.first(where: { $0.id == workflow.recipeID }) {
                guard await (try? store.save(workflow.recipe(from: recipe))) != nil else { continue }
                if workflow.name == recipe.name {
                    replaced.insert(recipe.id)
                }
            }
            try? manager.removeItem(at: file)
        }
        for id in replaced {
            try? await store.delete(id)
        }
        if (try? manager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
            try? manager.removeItem(at: directory)
        }
    }

    /// A workflow's file: `{"version": 1, "workflow": {...}}`.
    private struct Stored: Decodable {
        let workflow: Workflow
    }

    /// A workflow as it was kept.
    private struct Workflow: Decodable {
        let id: UUID
        let name: String
        let recipeID: UUID
        let adaptsToEachPhoto: Bool?
        let options: ExportOptions
        let naming: RecipeFiles.Naming?
        let destination: RecipeFiles.Destination
        let asks: Set<RecipeFiles.Setting>?

        /// The recipe this workflow becomes, with the look of `recipe`.
        func recipe(from recipe: Recipe) -> Recipe {
            var look = recipe.look
            if adaptsToEachPhoto == true {
                look.autoExposure = true
                look.autoWhiteBalance = true
            }
            return Recipe(
                id: id, name: name, from: look, filmModel: recipe.filmModel,
                files: RecipeFiles(
                    options: options, naming: naming ?? .nameAndFilm, destination: destination, asks: asks ?? [],
                ),
            )
        }
    }
}
