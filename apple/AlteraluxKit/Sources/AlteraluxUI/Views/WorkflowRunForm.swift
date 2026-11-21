import AlteraluxKit
import DesignSystem
import SwiftUI

/// The export sheet's form for developing the selected photos of the library with a workflow:
/// which workflow, and what it does with them.
struct WorkflowRunForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        FormSheet(
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
