import AlteraluxKit
import DesignSystem
import SwiftUI

/// The rows that name a recipe's files: the photo's name and the film, the photo's name, or the
/// photo's name and a text. In the editor the choice can be left open, to be asked each time.
struct RecipeNamingFields: View {
    @Binding var files: RecipeFiles
    /// Whether the choice can be left open: in the editor, not when it is being asked.
    let allowsAsking: Bool

    var body: some View {
        if allowsAsking {
            WindowPopUp(
                "File name", selection: ExportOptionsFields.asking(.naming, $files.asks, kind),
                options: ExportOptionsFields.askingOptions(Self.kinds),
            )
        } else {
            WindowPopUp("File name", selection: kind, options: Self.kinds)
        }
        if case .nameAndText = files.naming {
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
                switch files.naming {
                case .nameAndFilm: .nameAndFilm
                case .name: .name
                case .nameAndText: .nameAndText
                }
            },
            set: { kind in
                switch kind {
                case .nameAndFilm: files.naming = .nameAndFilm
                case .name: files.naming = .name
                case .nameAndText:
                    if case .nameAndText = files.naming {} else {
                        files.naming = .nameAndText(String(localized: "developed"))
                    }
                }
            },
        )
    }

    private var text: Binding<String> {
        Binding(
            get: {
                if case let .nameAndText(text) = files.naming {
                    text
                } else {
                    ""
                }
            },
            set: { files.naming = .nameAndText($0) },
        )
    }
}

/// The rows that say where a recipe writes: beside the photos, in a folder of a name beside
/// them, or in one folder, chosen with the system's panel as Save As does. In the editor the
/// choice can be left open, to be asked each time.
struct RecipeDestinationFields: View {
    @Binding var files: RecipeFiles
    /// Whether the choice can be left open: in the editor, not when it is being asked.
    let allowsAsking: Bool

    var body: some View {
        if allowsAsking {
            WindowPopUp(
                "Destination", selection: ExportOptionsFields.asking(.destination, $files.asks, kind),
                options: ExportOptionsFields.askingOptions(Self.kinds),
            )
        } else {
            WindowPopUp("Destination", selection: kind, options: Self.kinds)
        }
        switch files.destination {
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
                switch files.destination {
                case .sameFolder: .sameFolder
                case .besideOriginals: .subfolder
                case .folder: .folder
                }
            },
            set: { kind in
                switch kind {
                case .sameFolder: files.destination = .sameFolder
                case .subfolder:
                    if case .besideOriginals = files.destination {} else {
                        files.destination = .besideOriginals(folderName: AppModel.developedFolderName)
                    }
                case .folder: chooseFolder()
                }
            },
        )
    }

    private var folderName: Binding<String> {
        Binding(
            get: {
                if case let .besideOriginals(name) = files.destination {
                    name
                } else {
                    ""
                }
            },
            set: { files.destination = .besideOriginals(folderName: $0) },
        )
    }

    private func chooseFolder() {
        Task {
            if let bookmark = try? await AppModel.askForFolder() {
                files.destination = .folder(bookmark)
            }
        }
    }
}

/// The section that develops some photos with a recipe: which recipe, when there are several,
/// and the settings it leaves open; under it, what the recipe settles for the rest. The same in
/// the library's sheet and in the panel the Finder's photos bring.
struct RecipeRunSection: View {
    let recipes: [Recipe]
    /// The recipe chosen, with the answers to what it asks.
    @Binding var run: Recipe

    var body: some View {
        Section {
            if recipes.count > 1 {
                WindowPopUp("Recipe", selection: chosen, options: recipes.map { WindowPopUpOption($0.id, title: $0.name) })
            } else {
                LabeledContent("Recipe") {
                    Text(verbatim: run.name)
                }
            }
            if run.files.asks.contains(.format) {
                WindowPopUp("Format", selection: $run.files.options.format, options: ExportOptionsFields.formats)
            }
            if run.files.asks.contains(.size) {
                WindowPopUp("Size", selection: $run.files.options.longSide, options: ExportOptionsFields.sizes)
            }
            if run.files.asks.contains(.naming) {
                RecipeNamingFields(files: $run.files, allowsAsking: false)
            }
            if run.files.asks.contains(.destination) {
                RecipeDestinationFields(files: $run.files, allowsAsking: false)
            }
        } footer: {
            let settled = AppModel.settledSettings(of: run.files)
            if !settled.isEmpty {
                Text("The rest as the recipe says: \(settled)")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The recipe; choosing another starts from its own settings.
    private var chosen: Binding<Recipe.ID> {
        Binding(
            get: { run.id },
            set: { id in
                if let recipe = recipes.first(where: { $0.id == id }) {
                    run = recipe
                }
            },
        )
    }
}
