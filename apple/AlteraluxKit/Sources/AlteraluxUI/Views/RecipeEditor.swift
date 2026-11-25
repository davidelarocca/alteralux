import AlteraluxKit
import DesignSystem
import SwiftUI

/// A recipe being saved, changed or duplicated, for the editor's sheet.
struct RecipeDraft: Identifiable {
    var recipe: Recipe
    let kind: Kind

    enum Kind {
        /// The look on screen, saved as a new recipe.
        case new
        /// A recipe kept, being changed.
        case edit
        /// A copy of a recipe, not kept yet.
        case duplicate
    }

    var id: Recipe.ID {
        recipe.id
    }
}

/// The sheet that saves a new recipe, changes one or duplicates one: its name, and the files it
/// writes when photos are developed with it. A new recipe shows the files in a line, ready as
/// they are, with a button that opens them; a recipe being changed or duplicated shows them open.
struct RecipeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe
    @State private var showsFiles: Bool
    private let kind: RecipeDraft.Kind

    init(draft: RecipeDraft) {
        _recipe = State(initialValue: draft.recipe)
        _showsFiles = State(initialValue: draft.kind != .new)
        kind = draft.kind
    }

    var body: some View {
        FormSheet(
            title, message: message,
            confirm: SheetAction(Text("Save"), isEnabled: AppModel.canSave(recipe)) {
                let recipe = recipe
                dismiss()
                Task { await model.save(recipe) }
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            Section {
                TextField("Name", text: $recipe.name)
                RecipeLightRows(recipe: recipe)
            }
            if showsFiles {
                files
            } else {
                filesInALine
            }
        }
    }

    private var title: Text {
        switch kind {
        case .new: Text("Save as New Recipe")
        case .edit: Text("Edit Recipe")
        case .duplicate: Text("Duplicate Recipe")
        }
    }

    private var message: Text {
        switch kind {
        case .new: Text("The recipe keeps the look of this photo: everything but its white balance.")
        case .edit: Text("The look stays as it was saved: the name and the files can change.")
        case .duplicate: Text("The same look under another name, with files of its own.")
        }
    }

    /// The files as they are, in a line, and the way to change them.
    private var filesInALine: some View {
        Section {
            LabeledContent {
                Button("Edit…") { showsFiles = true }
            } label: {
                Text("Files")
                Text(verbatim: AppModel.summary(of: recipe.files))
            }
        } footer: {
            note(Text("Written when photos are developed with the recipe: from the library, or in the Finder with Develop with alteralux."))
        }
    }

    /// The files, in the order the user thinks of them: what they are, their names, where they go.
    @ViewBuilder private var files: some View {
        Section {
            ExportOptionsFields(options: $recipe.files.options, asks: $recipe.files.asks)
        } header: {
            Text("Files")
        } footer: {
            note(Text("Written when photos are developed with the recipe. A setting asked each time is chosen then: the rest is done alone."))
        }
        Section {
            RecipeNamingFields(files: $recipe.files, allowsAsking: true)
        } footer: {
            if !recipe.files.asks.contains(.naming) {
                note(Text("For example: “\(example)”"))
            }
        }
        Section {
            RecipeDestinationFields(files: $recipe.files, allowsAsking: true)
        } footer: {
            destinationNote
        }
    }

    /// What the destination chosen means for files already there.
    @ViewBuilder private var destinationNote: some View {
        if recipe.files.asks.contains(.destination) {
            note(Text("Asked each time, as Save As would."))
        } else {
            switch recipe.files.destination {
            case .sameFolder:
                note(Text("The files appear in the folder of each photo. A file of the same name is never replaced: the new one takes a number."))
            case .besideOriginals:
                note(Text("A folder of this name is made beside each photo. If the photos were developed there before, you are asked what to do."))
            case .folder:
                note(Text("Every photo goes into this folder. If it was developed there before, you are asked what to do."))
            }
        }
    }

    private func note(_ text: Text) -> some View {
        text
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The name a photo called IMG_0042 would get, with the recipe's film.
    private var example: String {
        let film = model.films.first { $0.id == recipe.look.filmID }?.displayName ?? "Kodak Portra 400"
        let name = AppModel.exportName(source: URL(fileURLWithPath: "/IMG_0042.ARW"), film: film, files: recipe.files)
        return "\(name).\(recipe.files.options.format.fileExtension)"
    }
}

/// Where a recipe starts each photo from: the exposure and the white balance it was saved with,
/// automatic or not. A recipe's white balance is never a value: when it is not automatic, each
/// photo keeps its own.
struct RecipeLightRows: View {
    let recipe: Recipe

    var body: some View {
        LabeledContent("Exposure") {
            recipe.look.autoExposure ? Text("Auto") : Text("As saved")
        }
        LabeledContent("White balance") {
            recipe.look.autoWhiteBalance ? Text("Auto") : Text("Each photo’s own")
        }
    }
}

#Preview("A new recipe") {
    RecipeEditor(draft: RecipeDraft(recipe: Recipe(name: "", from: DevelopSettings()), kind: .new))
        .environment(AppModel())
}

#Preview("A recipe being changed") {
    let files = RecipeFiles(naming: .nameAndText("web"), destination: .besideOriginals(folderName: "Web"), asks: [.size])
    RecipeEditor(draft: RecipeDraft(recipe: Recipe(name: "Portra at dusk", from: DevelopSettings(), files: files), kind: .edit))
        .environment(AppModel())
}
