import AlteraluxKit
import DesignSystem
import SwiftUI

/// The rows that name a workflow's files: the photo's name and the film, the photo's name, or the
/// photo's name and a text. In the editor the choice can be left open, to be asked each time.
struct WorkflowNamingFields: View {
    @Binding var workflow: Workflow
    /// Whether the choice can be left open: in the editor, not when it is being asked.
    let allowsAsking: Bool

    var body: some View {
        if allowsAsking {
            WindowPopUp(
                "File name", selection: ExportOptionsFields.asking(.naming, $workflow.asks, kind),
                options: ExportOptionsFields.askingOptions(Self.kinds),
            )
        } else {
            WindowPopUp("File name", selection: kind, options: Self.kinds)
        }
        if case .nameAndText = workflow.naming {
            TextField("Text", text: text)
        }
    }

    enum Kind: Hashable {
        case nameAndFilm, name, nameAndText
    }

    static var kinds: [WindowPopUpOption<Kind>] {
        [
            WindowPopUpOption(.nameAndFilm, title: String(localized: "Photo’s name and film")),
            WindowPopUpOption(.name, title: String(localized: "Photo’s name")),
            WindowPopUpOption(.nameAndText, title: String(localized: "Photo’s name and a text")),
        ]
    }

    private var kind: Binding<Kind> {
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
                case .nameAndText:
                    if case .nameAndText = workflow.naming {} else {
                        workflow.naming = .nameAndText(String(localized: "developed"))
                    }
                }
            },
        )
    }

    private var text: Binding<String> {
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
}

/// The rows that say where a workflow writes: beside the photos, in a folder of a name beside
/// them, or in one folder, chosen with the system's panel as Save As does. In the editor the
/// choice can be left open, to be asked each time.
struct WorkflowDestinationFields: View {
    @Binding var workflow: Workflow
    /// Whether the choice can be left open: in the editor, not when it is being asked.
    let allowsAsking: Bool

    var body: some View {
        if allowsAsking {
            WindowPopUp(
                "Destination", selection: ExportOptionsFields.asking(.destination, $workflow.asks, kind),
                options: ExportOptionsFields.askingOptions(Self.kinds),
            )
        } else {
            WindowPopUp("Destination", selection: kind, options: Self.kinds)
        }
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
    }

    enum Kind: Hashable {
        case sameFolder, subfolder, folder
    }

    static var kinds: [WindowPopUpOption<Kind>] {
        [
            WindowPopUpOption(.sameFolder, title: String(localized: "Beside the photos")),
            WindowPopUpOption(.subfolder, title: String(localized: "In a folder beside the photos")),
            WindowPopUpOption(.folder, title: String(localized: "In one folder")),
        ]
    }

    /// Where the files go. Choosing one folder asks for it at once, and stays where it was when
    /// none is chosen.
    private var kind: Binding<Kind> {
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
                case .subfolder:
                    if case .besideOriginals = workflow.destination {} else {
                        workflow.destination = .besideOriginals(folderName: AppModel.developedFolderName)
                    }
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
            if let bookmark = try? await AppModel.askForFolder() {
                workflow.destination = .folder(bookmark)
            }
        }
    }
}

/// The section that runs a workflow on some photos: which workflow, when there are several, its
/// recipe, and the settings it leaves open; under it, what the workflow settles for the rest.
/// The same in the library's sheet and in the panel the Finder's photos bring.
struct WorkflowRunSection: View {
    let workflows: [Workflow]
    let recipes: [Recipe]
    /// The workflow chosen, with the answers to what it asks.
    @Binding var run: Workflow

    var body: some View {
        Section {
            if workflows.count > 1 {
                WindowPopUp("Workflow", selection: chosen, options: workflows.map { WindowPopUpOption($0.id, title: $0.name) })
            }
            LabeledContent("Recipe") {
                Text(verbatim: recipes.first { $0.id == run.recipeID }?.name ?? "")
            }
            if run.asks.contains(.format) {
                WindowPopUp("Format", selection: $run.options.format, options: ExportOptionsFields.formats)
            }
            if run.asks.contains(.size) {
                WindowPopUp("Size", selection: $run.options.longSide, options: ExportOptionsFields.sizes)
            }
            if run.asks.contains(.naming) {
                WorkflowNamingFields(workflow: $run, allowsAsking: false)
            }
            if run.asks.contains(.destination) {
                WorkflowDestinationFields(workflow: $run, allowsAsking: false)
            }
        } footer: {
            let settled = AppModel.settledSettings(of: run)
            if !settled.isEmpty {
                Text("The rest as the workflow says: \(settled)")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The workflow; choosing another starts from its own settings.
    private var chosen: Binding<Workflow.ID> {
        Binding(
            get: { run.id },
            set: { id in
                if let workflow = workflows.first(where: { $0.id == id }) {
                    run = workflow
                }
            },
        )
    }
}
