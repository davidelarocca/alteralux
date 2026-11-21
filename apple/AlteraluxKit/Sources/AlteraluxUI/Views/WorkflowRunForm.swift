import AlteraluxKit
import DesignSystem
import SwiftUI

/// The export sheet's form for developing the selected photos of the library with a workflow:
/// which workflow, and the settings it leaves open.
struct WorkflowRunForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The workflow chosen, with the answers to what it asks; at first the one chosen last.
    @State private var answered: Workflow?

    var body: some View {
        let run = answered ?? model.chosenWorkflow
        FormSheet(
            Text("Develop \(model.photosToExport.count) Photos"),
            message: Text("Each photo is written as a file with the workflow’s recipe, and keeps its own adjustments."),
            confirm: SheetAction(Text("Develop"), isEnabled: run != nil) {
                Task { await model.developWithWorkflow(run) }
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            if let run {
                WorkflowRunSection(
                    workflows: model.workflows, recipes: model.recipes,
                    run: Binding(get: { answered ?? run }, set: { answered = $0 }),
                )
            }
        }
    }
}
