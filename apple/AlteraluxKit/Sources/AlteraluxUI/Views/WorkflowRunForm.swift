import AlteraluxKit
import DesignSystem
import SwiftUI

/// The export sheet's form for developing photos with a workflow (the selected photos of the
/// library, or photos sent from the Finder): which workflow, and what it does with them. With no
/// workflow yet, it leads to the window where they are made.
struct WorkflowRunForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.workflows.isEmpty {
            noWorkflows
        } else {
            form
        }
    }

    private var noWorkflows: some View {
        FormSheet(
            Text("Develop \(model.photosToExport.count) Photos"),
            message: Text("There is no workflow yet. Make one in Recipes and Workflows: a recipe and the files it writes."),
            confirm: SheetAction(Text("Recipes and Workflows…")) {
                dismiss()
                openWindow(id: RecipesWindow.id)
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            EmptyView()
        }
    }

    private var form: some View {
        @Bindable var model = model

        return FormSheet(
            Text("Develop \(model.photosToExport.count) Photos"),
            message: Text("Each photo is written as a file with the workflow’s recipe, and keeps its own adjustments."),
            confirm: SheetAction(Text("Develop"), isEnabled: model.chosenWorkflow != nil) {
                Task { await model.developWithWorkflow() }
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            Section {
                WindowPopUp(
                    "Workflow", selection: $model.exportWorkflow,
                    options: model.workflows.map { WindowPopUpOption(Optional($0.id), title: $0.name) },
                )
                if let workflow = model.chosenWorkflow {
                    LabeledContent("Recipe") {
                        Text(verbatim: model.recipe(of: workflow)?.name ?? "")
                    }
                }
            } footer: {
                if let workflow = model.chosenWorkflow {
                    Text(verbatim: model.summary(of: workflow))
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
