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
                ExportOptionsFields(options: $workflow.options)
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
            WindowPopUp("File name", selection: namingKind, options: [
                WindowPopUpOption(NamingKind.nameAndFilm, title: String(localized: "Photo’s name and film")),
                WindowPopUpOption(NamingKind.name, title: String(localized: "Photo’s name")),
                WindowPopUpOption(NamingKind.nameAndText, title: String(localized: "Photo’s name and a text")),
            ])
            if case .nameAndText = workflow.naming {
                TextField("Text", text: namingText)
            }
        } footer: {
            note(Text("For example: “\(example)”"))
        }
    }

    /// Where the files go: beside each photo, in a folder of a name beside it, or in one folder
    /// chosen once.
    private var destination: some View {
        Section {
            WindowPopUp("Destination", selection: destinationKind, options: [
                WindowPopUpOption(DestinationKind.sameFolder, title: String(localized: "Beside the photos")),
                WindowPopUpOption(DestinationKind.subfolder, title: String(localized: "In a folder beside the photos")),
                WindowPopUpOption(DestinationKind.folder, title: String(localized: "In one folder")),
            ])
            switch workflow.destination {
            case .sameFolder:
                EmptyView()
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

    // MARK: - Choices

    private enum NamingKind: Hashable {
        case nameAndFilm, name, nameAndText
    }

    private enum DestinationKind: Hashable {
        case sameFolder, subfolder, folder
    }

    private var namingKind: Binding<NamingKind> {
        Binding(
            get: {
                switch workflow.naming {
                case .nameAndFilm: .nameAndFilm
                case .name: .name
                case .nameAndText: .nameAndText
                }
            },
            set: { kind in
                switch kind {
                case .nameAndFilm: workflow.naming = .nameAndFilm
                case .name: workflow.naming = .name
                case .nameAndText: workflow.naming = .nameAndText(String(localized: "developed"))
                }
            },
        )
    }

    private var namingText: Binding<String> {
        Binding(
            get: {
                if case let .nameAndText(text) = workflow.naming {
                    text
                } else {
                    ""
                }
            },
            set: { workflow.naming = .nameAndText($0) },
        )
    }

    /// Where the files go. Choosing one folder asks for it at once, and stays where it was when
    /// none is chosen.
    private var destinationKind: Binding<DestinationKind> {
        Binding(
            get: {
                switch workflow.destination {
                case .sameFolder: .sameFolder
                case .besideOriginals: .subfolder
                case .folder: .folder
                }
            },
            set: { kind in
                switch kind {
                case .sameFolder: workflow.destination = .sameFolder
                case .subfolder: workflow.destination = .besideOriginals(folderName: AppModel.developedFolderName)
                case .folder: chooseFolder()
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
