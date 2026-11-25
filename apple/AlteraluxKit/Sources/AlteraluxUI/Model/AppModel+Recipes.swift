import AlteraluxKit
import Foundation

// Recipes, and giving the look of one photo to others: saving, changing and deleting recipes,
// applying one to the photo on screen or to the selection of the library, copying and pasting
// adjustments. A look is every adjustment but the white balance, which stays each photo's own
// (ADR 0009).

/// The adjustments of one photo, and whether they are kept with it or it has none yet.
struct PhotoAdjustments: Equatable {
    let photo: URL
    let settings: DevelopSettings
    let isKept: Bool
}

extension AppModel {
    // MARK: - Recipes

    /// Reads the recipes again from where they are kept. The first time, the workflows kept
    /// before recipes wrote files become recipes (ADR 0021).
    func loadRecipes() async {
        if !hasMigratedWorkflows {
            hasMigratedWorkflows = true
            await WorkflowMigration.run(workflows: workflowsDirectory, into: recipeStore)
        }
        recipes = await recipeStore.all()
    }

    /// Whether `name` can be the name of a recipe: anything but blank.
    static func isRecipeName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A recipe with the look of the photo on screen, not kept yet: the save sheet names it and
    /// may change the files it writes.
    func newRecipe(named name: String = "") -> Recipe {
        Recipe(name: name, from: settings)
    }

    /// A copy of `recipe`, not kept yet: the same look under a name that says so, with the same
    /// files, to change into another way of writing the look (ADR 0021).
    func copy(of recipe: Recipe) -> Recipe {
        Recipe(
            name: String(localized: "\(recipe.name) copy", comment: "The name of a duplicated recipe"),
            from: recipe.look, filmModel: recipe.filmModel, files: recipe.files,
        )
    }

    /// Keeps a recipe, new or changed: its name and the files it writes. The name, the name of a
    /// folder beside the originals and the text added to the files' names are trimmed; a recipe
    /// that lacks one of them is not kept. The photos that received it are not touched.
    func save(_ recipe: Recipe) async {
        var recipe = recipe
        recipe.name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .besideOriginals(folderName) = recipe.files.destination {
            recipe.files.destination = .besideOriginals(folderName: folderName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if case let .nameAndText(text) = recipe.files.naming {
            recipe.files.naming = .nameAndText(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard Self.canSave(recipe) else { return }
        do {
            try await recipeStore.save(recipe)
        } catch {
            alertMessage = String(localized: "The recipe “\(recipe.name)” could not be saved.")
        }
        await loadRecipes()
    }

    /// Whether a recipe can be kept as it is: it has a name, a folder to write to, and a text
    /// for the files' names when it adds one.
    static func canSave(_ recipe: Recipe) -> Bool {
        isRecipeName(recipe.name) && canWrite(recipe.files)
    }

    /// Deletes a recipe. The photos that received it keep their adjustments, and the files it
    /// wrote stay where they are.
    func delete(_ recipe: Recipe) async {
        do {
            try await recipeStore.delete(recipe.id)
        } catch {
            alertMessage = String(localized: "The recipe “\(recipe.name)” could not be deleted.")
        }
        await loadRecipes()
    }

    // MARK: - Giving a look

    /// Gives a recipe to the photo on screen. One undo takes it back whole.
    func apply(_ recipe: Recipe) {
        give { recipe.applied(to: $0) }
    }

    /// Gives a recipe to the selected photos of the library. One undo takes it back from all.
    func applyToSelection(_ recipe: Recipe) {
        apply(recipe, to: selectedPhotos)
    }

    /// Gives a recipe to photos, whether they are in the strip or not. One undo takes it back
    /// from all.
    func apply(_ recipe: Recipe, to photos: [URL]) {
        give({ recipe.applied(to: $0) }, to: photos)
    }

    /// Whether the selected photos of the library can receive a look: discarded photos are
    /// taken back first.
    var canGiveLookToSelection: Bool {
        !library.selection.isEmpty && library.filter != .discarded
    }

    /// Gives the photo on screen the look of `look`, as one change: one step of undo, kept at
    /// once.
    func giveLook(_ look: DevelopSettings) {
        give { $0.takingLook(of: look) }
    }

    /// Gives photos the look of `look`, whether they are in the strip or not, as one step of
    /// undo for all of them.
    func giveLook(_ look: DevelopSettings, to photos: [URL]) {
        give({ $0.takingLook(of: look) }, to: photos)
    }

    /// Changes the adjustments of the photo on screen with `change`, as one change: one step of
    /// undo, kept at once.
    private func give(_ change: (DevelopSettings) -> DevelopSettings) {
        guard hasPhoto else { return }
        closeChange()
        settings = change(settings)
        closeChange()
    }

    /// Changes the adjustments of photos with `change`, whether they are in the strip or not, as
    /// one step of undo for all of them.
    private func give(_ change: (DevelopSettings) -> DevelopSettings, to photos: [URL]) {
        closeChange()
        set(photos.map { photo in
            PhotoAdjustments(photo: photo, settings: change(adjustments(of: photo).settings), isKept: true)
        })
    }

    /// The adjustments of a photo as they are now: the ones in the strip, the ones kept with it,
    /// or the ones a photo starts with.
    func adjustments(of photo: URL) -> PhotoAdjustments {
        let kept = history.kept(for: photo)
        let shown = photos.first { $0.url == photo }?.settings
        return PhotoAdjustments(photo: photo, settings: shown ?? kept ?? DevelopSettings(), isKept: kept != nil)
    }

    /// Ends the change in progress on the photo on screen, so that what follows starts from
    /// adjustments that stand still and are a step of their own.
    func closeChange() {
        settingsDidChange()
        settleChange()
    }

    /// Puts adjustments on photos, in the strip and on disk, and registers the way back as one
    /// step of undo.
    func set(_ changes: [PhotoAdjustments]) {
        guard !changes.isEmpty else { return }
        let before = changes.map { adjustments(of: $0.photo) }
        for change in changes {
            if let item = photos.first(where: { $0.url == change.photo }) {
                put(change.settings, on: item)
                item.hasAdjustments = change.isKept
            }
        }
        history.keep(changes.map { ($0.photo, $0.isKept ? $0.settings : nil) })
        if let undoManager = history.undoManager {
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self) { model in
                model.set(before)
            }
            undoManager.endUndoGrouping()
        }
        // The marks of the grid follow once the photos carry their adjustments.
        Task { [history, library] in
            await history.waitUntilSaved()
            for change in changes {
                library.noteAdjustments(of: change.photo)
            }
        }
    }

    // MARK: - Copy and paste

    /// Whether there are adjustments to copy: the photo on screen's, or those of the one photo
    /// selected in the library.
    var canCopyAdjustments: Bool {
        showsLibrary ? library.selection.count == 1 : hasPhoto
    }

    /// Copies the adjustments of the photo on screen, or of the photo selected in the library.
    func copyAdjustments() {
        guard canCopyAdjustments else { return }
        if showsLibrary {
            if let photo = selectedPhotos.first {
                copiedAdjustments = adjustments(of: photo).settings
            }
        } else {
            closeChange()
            copiedAdjustments = settings
        }
    }

    var canPasteAdjustments: Bool {
        copiedAdjustments != nil && (showsLibrary ? canGiveLookToSelection : hasPhoto)
    }

    /// Gives the copied look to the photo on screen, or to the selected photos of the library.
    /// Like a recipe, it leaves each photo's white balance alone.
    func pasteAdjustments() {
        guard canPasteAdjustments, let copiedAdjustments else { return }
        if showsLibrary {
            giveLook(copiedAdjustments, to: selectedPhotos)
        } else {
            giveLook(copiedAdjustments)
        }
    }
}
