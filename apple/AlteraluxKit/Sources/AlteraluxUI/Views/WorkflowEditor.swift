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

/// The sheet that makes or changes a workflow: its name, the files it writes (the export's own
/// options) and where it writes them.
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
            message: Text("Develops photos with the recipe “\(model.recipe(of: workflow)?.name ?? "")” and writes them as files."),
            confirm: SheetAction(Text("Save"), isEnabled: AppModel.canSave(workflow)) {
                let workflow = workflow
                dismiss()
                Task { await model.save(workflow) }
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            TextField("Name", text: $workflow.name)
            Section {
                ExportOptionsFields(options: $workflow.options)
            }
            destination
        }
    }

    /// Where the files go: a folder of a name beside each photo, or one folder chosen once.
    private var destination: some View {
        Section {
            WindowPopUp("Destination", selection: isBesideOriginals, options: [
                WindowPopUpOption(true, title: String(localized: "Beside the originals")),
                WindowPopUpOption(false, title: String(localized: "A folder")),
            ])
            switch workflow.destination {
            case .besideOriginals:
                TextField("Folder name", text: folderName)
            case let .folder(bookmark):
                LabeledContent("Folder") {
                    HStack(spacing: Spacing.s) {
                        Text(verbatim: bookmark.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                    }
                }
            }
        } footer: {
            Group {
                switch workflow.destination {
                case .besideOriginals:
                    Text("A folder of this name is made beside each photo. If the photos were developed there before, you are asked what to do.")
                case .folder:
                    Text("Every photo goes into this folder. If it was developed there before, you are asked what to do.")
                }
            }
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Whether the files go beside the originals. Choosing a folder asks for it at once, and
    /// stays beside the originals when none is chosen.
    private var isBesideOriginals: Binding<Bool> {
        Binding(
            get: {
                if case .besideOriginals = workflow.destination {
                    true
                } else {
                    false
                }
            },
            set: { beside in
                if beside {
                    workflow.destination = .besideOriginals(folderName: AppModel.developedFolderName)
                } else {
                    chooseFolder()
                }
            },
        )
    }

    private var folderName: Binding<String> {
        Binding(
            get: {
                if case let .besideOriginals(name) = workflow.destination {
                    name
                } else {
                    ""
                }
            },
            set: { workflow.destination = .besideOriginals(folderName: $0) },
        )
    }

    private func chooseFolder() {
        Task {
            if let bookmark = await model.chooseWorkflowFolder() {
                workflow.destination = .folder(bookmark)
            }
        }
    }
}
