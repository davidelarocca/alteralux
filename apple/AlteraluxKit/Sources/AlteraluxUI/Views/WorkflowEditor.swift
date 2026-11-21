import AlteraluxKit
import DesignSystem
import SwiftUI

/// A workflow being made or changed, for the editor's sheet.
struct WorkflowDraft: Identifiable {
    var workflow: Workflow
    /// Whether it is a new workflow, not kept yet.
    let isNew: Bool

    var id: Workflow.ID {
        workflow.id
    }
}

/// The sheet that makes or changes a workflow, in the order the user thinks of it: which recipe
/// and whether it adapts to each photo, the files it writes, their names, and where they go.
struct WorkflowEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var workflow: Workflow
    private let isNew: Bool

    init(draft: WorkflowDraft) {
        _workflow = State(initialValue: draft.workflow)
        isNew = draft.isNew
    }

    var body: some View {
        FormSheet(
            isNew ? Text("New Workflow") : Text("Edit Workflow"),
            message: Text("A workflow develops photos with a recipe and writes them as files. In the Finder: Develop with alteralux."),
            confirm: SheetAction(Text("Save"), isEnabled: AppModel.canSave(workflow)) {
                let workflow = workflow
                dismiss()
                Task { await model.save(workflow) }
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            TextField("Name", text: $workflow.name)
            recipe
            Section {
                ExportOptionsFields(options: $workflow.options, asks: $workflow.asks)
            } footer: {
                note(Text("A setting asked each time is chosen when the workflow runs: the rest is done alone."))
            }
            naming
            destination
        }
    }

    /// The recipe, and whether each photo starts from its own light.
    private var recipe: some View {
        Section {
            WindowPopUp(
                "Recipe", selection: $workflow.recipeID,
                options: model.recipes.map { WindowPopUpOption($0.id, title: $0.name) },
            )
            Toggle("Adapts to each photo", isOn: $workflow.adaptsToEachPhoto)
        } footer: {
            note(Text("Adapting, each photo starts from its own exposure, and from an automatic white balance where the camera’s is far off."))
        }
    }

    /// What the files are called.
    private var naming: some View {
        Section {
            WorkflowNamingFields(workflow: $workflow, allowsAsking: true)
        } footer: {
            if !workflow.asks.contains(.naming) {
                note(Text("For example: “\(example)”"))
            }
        }
    }

    /// Where the files go: beside each photo, in a folder of a name beside it, or in one folder
    /// chosen once.
    private var destination: some View {
        Section {
            WorkflowDestinationFields(workflow: $workflow, allowsAsking: true)
        } footer: {
            if workflow.asks.contains(.destination) {
                note(Text("Asked each time, as Save As would."))
            } else {
                switch workflow.destination {
                case .sameFolder:
                    note(Text("The files appear in the folder of each photo. A file of the same name is never replaced: the new one takes a number."))
                case .besideOriginals:
                    note(Text("A folder of this name is made beside each photo. If the photos were developed there before, you are asked what to do."))
                case .folder:
                    note(Text("Every photo goes into this folder. If it was developed there before, you are asked what to do."))
                }
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
        let film = model.recipe(of: workflow).flatMap { recipe in
            model.films.first { $0.id == recipe.look.filmID }?.displayName
        } ?? "Kodak Portra 400"
        let name = AppModel.exportName(source: URL(fileURLWithPath: "/IMG_0042.ARW"), film: film, workflow: workflow)
        return "\(name).\(workflow.options.format.fileExtension)"
    }
}
