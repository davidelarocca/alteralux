import AlteraluxKit
import AppKit
import DesignSystem
import SwiftUI

/// What a photo's menu asks before it acts, with the photos it then acts on.
enum PhotoQuestion: Equatable {
    /// The name of a new tag for these photos.
    case newTag([URL])
    /// A new name for this photo.
    case rename(URL)
    /// Whether to move these photos to the Trash: one click must not empty a folder.
    case trash([URL])
}

/// The menu of a photo of the library's grid, opened with a secondary click: what the bar of
/// the selection offers, with Develop, the Finder's actions on the file (Show in Finder, Open
/// With, Share, Duplicate, Rename, Tags, Move to Trash) and turning the photo. As in the
/// Finder, a photo clicked outside the selection becomes the selection when one of its actions
/// is taken. With several photos the actions say how many they act on, as in Photos.
struct LibraryPhotoMenu: View {
    @Environment(AppModel.self) private var model
    let photo: URL
    /// Asks for a name before acting: for a new tag or a new name of the photo.
    let ask: (PhotoQuestion) -> Void
    /// Opens the system's share picker for these photos, pointing at the one clicked.
    let share: ([URL]) -> Void

    var body: some View {
        let count = targets.count
        Button("Develop") { model.develop(photo) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets) }
        OpenWithMenu(photo: photo, photos: targets)
        Divider()
        Menu("Recipe") {
            ForEach(model.recipes) { recipe in
                Button(recipe.name) { act { model.applyToSelection(recipe) } }
            }
        }
        .disabled(model.recipes.isEmpty)
        Button { act { model.presentExport() } } label: {
            count > 1 ? Text("Export \(count) Photos…") : Text("Export…")
        }
        Menu("Develop with Recipe") {
            ForEach(model.recipes) { recipe in
                Button(recipe.name) { act { model.presentRecipeRun(recipe) } }
            }
        }
        .disabled(model.recipes.isEmpty)
        Button("Share…") { act { share(targets) } }
        Divider()
        Menu("Move to") {
            ForEach(destinations, id: \.url) { folder in
                Button(folder.name) { act { Task { await model.moveSelection(to: folder.url) } } }
            }
        }
        .disabled(destinations.isEmpty)
        Menu("Copy to") {
            ForEach(destinations, id: \.url) { folder in
                Button(folder.name) { act { Task { await model.copySelection(to: folder.url) } } }
            }
        }
        .disabled(destinations.isEmpty)
        Button { act { Task { await model.duplicateSelection() } } } label: {
            count > 1 ? Text("Duplicate \(count) Photos") : Text("Duplicate")
        }
        if count == 1 {
            Button("Rename…") { act { ask(.rename(photo)) } }
        }
        Divider()
        PhotoTagMenu(photos: targets, act: act, ask: ask)
        Divider()
        Button("Copy Adjustments") { act { model.copyAdjustments() } }
            .disabled(count != 1)
        Button("Paste Adjustments") { act { model.pasteAdjustments() } }
            .disabled(model.copiedAdjustments == nil || model.library.filter == .discarded)
        Button { act { model.resetAdjustmentsOfSelection() } } label: {
            count > 1 ? Text("Reset Adjustments of \(count) Photos") : Text("Reset Adjustments")
        }
        .disabled(!targets.contains(where: model.library.adjusted.contains))
        Button("Rotate Left") { act { model.turnSelection(clockwise: false) } }
        Button("Rotate Right") { act { model.turnSelection(clockwise: true) } }
        Divider()
        discardButton(count: count)
        Button { act { ask(.trash(targets)) } } label: {
            count > 1 ? Text("Move \(count) Photos to Trash") : Text("Move to Trash")
        }
    }

    @ViewBuilder
    private func discardButton(count: Int) -> some View {
        if model.library.filter == .discarded {
            Button { act { model.discardSelection() } } label: {
                count > 1 ? Text("Take Back \(count) Photos") : Text("Take Back")
            }
        } else {
            Button { act { model.discardSelection() } } label: {
                count > 1 ? Text("Discard \(count) Photos") : Text("Discard")
            }
        }
    }

    /// The photos an action goes to: the selection when the photo is in it, the photo alone
    /// otherwise.
    private var targets: [URL] {
        model.library.selection.contains(photo) ? model.selectedPhotos : [photo]
    }

    /// The folders of the library a photo can go to, the folder on screen left out.
    private var destinations: [(url: URL, name: String)] {
        model.library.destinations.filter { $0.url != model.library.selectedFolder }.map { ($0.url, $0.name) }
    }

    /// Makes the photo the selection when it is not in it, then acts on the selection.
    private func act(_ action: () -> Void) {
        if !model.library.selection.contains(photo) {
            model.library.click(photo)
        }
        action()
    }
}

/// The Tags submenu of a photo's menu: the tags, as the Finder lists them, each with its dot and
/// a check when every photo carries it: choosing one puts it on or takes it off. Under them, a
/// new tag by its name.
private struct PhotoTagMenu: View {
    @Environment(AppModel.self) private var model
    /// The photos the tags are put on.
    let photos: [URL]
    /// What an action goes through: the library's menu makes its photo the selection first.
    var act: (() -> Void) -> Void = { $0() }
    /// Asks for the name of a new tag.
    let ask: (PhotoQuestion) -> Void

    var body: some View {
        let choices = model.tagChoices(for: photos)
        Menu("Tags") {
            ForEach(choices, id: \.name) { choice in
                Toggle(isOn: Binding(
                    get: { choice.carriedBy == photos.count },
                    set: { _ in act { model.toggleTag(choice.name, color: choice.color, on: photos) } },
                )) {
                    Label {
                        Text(verbatim: choice.name)
                    } icon: {
                        FinderTag(name: choice.name, color: choice.color).menuDot
                    }
                }
                // A toggle in a menu draws its title alone unless asked for the icon too.
                .labelStyle(.titleAndIcon)
            }
            Divider()
            Button("New Tag…") { act { ask(.newTag(photos)) } }
        }
    }
}

/// The menu of a photo of the strip, opened with a secondary click: what is done to a photo
/// while a series is developed, in the order of the library's menu. It acts on the photo it was
/// opened on, and the photo on screen stays. Discard takes the photo out of the strip, as it
/// takes it out of the grid. What arranges the files (Open With, Move to, Copy to, Duplicate,
/// Rename), turning and developing with a recipe stay in the library.
struct StripPhotoMenu: View {
    @Environment(AppModel.self) private var model
    let item: PhotoItem
    /// Asks before acting: the name of a new tag, whether to move the photo to the Trash.
    let ask: (PhotoQuestion) -> Void
    /// Opens the system's share picker for the photo, pointing at its thumbnail.
    let share: ([URL]) -> Void

    var body: some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        Divider()
        Menu("Recipe") {
            ForEach(model.recipes) { recipe in
                Button(recipe.name) { model.apply(recipe, to: item) }
            }
        }
        .disabled(model.recipes.isEmpty)
        Button("Export…") { model.presentExport(of: item) }
            .disabled(!model.canPresentExport(of: item))
        Button("Share…") { share([item.url]) }
        Divider()
        PhotoTagMenu(photos: [item.url], ask: ask)
        Divider()
        Button("Copy Adjustments") { model.copyAdjustments(of: item) }
        Button("Paste Adjustments") { model.pasteAdjustments(on: item) }
            .disabled(model.copiedAdjustments == nil)
        Button("Reset Adjustments") { model.resetAdjustments(of: item) }
            .disabled(!model.canResetAdjustments(of: item))
        Divider()
        Button(model.discardKind(of: item).title) { model.discard(item) }
        Button("Move to Trash") { ask(.trash([item.url])) }
    }
}

extension AppModel.StripDiscard {
    /// What the command is called: what it does to the photo.
    var title: LocalizedStringKey {
        switch self {
        case .discard: "Discard"
        case .takeBack: "Take Back"
        case .remove: "Remove from Strip"
        }
    }
}

/// The apps that open a photo, as the Finder's Open With lists them: the usual one first, each
/// with its icon. Choosing one opens the photos in it, as they are on disk.
private struct OpenWithMenu: View {
    let photo: URL
    let photos: [URL]

    var body: some View {
        let apps = Self.apps(opening: photo)
        Menu("Open With") {
            ForEach(apps, id: \.self) { app in
                Button {
                    NSWorkspace.shared.open(photos, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                } label: {
                    Label {
                        Text(verbatim: FileManager.default.displayName(atPath: app.path))
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    }
                }
            }
        }
        .disabled(apps.isEmpty)
    }

    /// The apps that open the photo, the default one first, this app left out.
    private static func apps(opening photo: URL) -> [URL] {
        let workspace = NSWorkspace.shared
        let own = Bundle.main.bundleURL.standardizedFileURL
        let usual = workspace.urlForApplication(toOpen: photo)
        let others = workspace.urlsForApplications(toOpen: photo)
            .filter { $0 != usual }
            .sorted { FileManager.default.displayName(atPath: $0.path) < FileManager.default.displayName(atPath: $1.path) }
        return ([usual].compactMap(\.self) + others).filter { $0.standardizedFileURL != own }
    }
}

/// What a photo's menu asks before it acts: a new tag for its photos, with its name and color,
/// in a sheet; a new name for a photo, in the system's alert; whether to move its photos
/// to the Trash, in the system's confirmation. The field starts with the photo's
/// name, its extension left out: it stays.
struct PhotoQuestionAlerts: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var question: PhotoQuestion?
    @State private var name = ""
    /// The photos of the last question: what it shows while it closes, the question gone.
    @State private var asked: [URL] = []

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isTagging) {
                NewTagSheet(photos: tagged)
                    .environment(model)
            }
            .alert("Rename Photo", isPresented: isRenaming) {
                TextField("Name", text: $name)
                Button("Rename") {
                    if case let .rename(photo) = question {
                        let name = name
                        Task { await model.rename(photo, to: name) }
                    }
                }
                .disabled(!AppModel.isPhotoName(name))
                Button("Cancel", role: .cancel) {}
            } message: {
                if case let .rename(photo) = question, !photo.pathExtension.isEmpty {
                    Text("The photo keeps its kind: “.\(photo.pathExtension)” stays at the end of its name.")
                }
            }
            .confirmationDialog(trashQuestion, isPresented: isTrashing) {
                Button("Move to Trash", role: .destructive) {
                    let photos = trashed
                    Task { await model.trash(photos) }
                }
            } message: {
                if trashed.count == 1 {
                    Text("You can put it back from the Trash in the Finder.")
                } else {
                    Text("You can put them back from the Trash in the Finder.")
                }
            }
            .onChange(of: question) { _, question in
                switch question {
                case let .rename(photo):
                    name = photo.deletingPathExtension().lastPathComponent
                case let .newTag(photos), let .trash(photos):
                    name = ""
                    asked = photos
                case nil:
                    name = ""
                }
            }
    }

    /// The question before the Trash: the photo by its name, or how many.
    private var trashQuestion: Text {
        let photos = trashed
        if photos.count == 1, let photo = photos.first {
            return Text("Move “\(photo.lastPathComponent)” to the Trash?")
        }
        return Text("Move \(photos.count) photos to the Trash?")
    }

    /// The photos a new tag is asked for.
    private var tagged: [URL] {
        if case let .newTag(photos) = question {
            photos
        } else {
            asked
        }
    }

    /// The photos asked about before the Trash.
    private var trashed: [URL] {
        if case let .trash(photos) = question {
            photos
        } else {
            asked
        }
    }

    private var isTagging: Binding<Bool> {
        isAsking {
            if case .newTag = $0 {
                true
            } else {
                false
            }
        }
    }

    private var isTrashing: Binding<Bool> {
        isAsking {
            if case .trash = $0 {
                true
            } else {
                false
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        isAsking {
            if case .rename = $0 {
                true
            } else {
                false
            }
        }
    }

    /// Whether the question on screen is of one kind; closing it takes the question away.
    private func isAsking(_ isKind: @escaping (PhotoQuestion) -> Bool) -> Binding<Bool> {
        Binding(get: { question.map(isKind) ?? false }, set: {
            if !$0 {
                question = nil
            }
        })
    }
}

/// The menu of the photo being developed, opened with a secondary click: its adjustments,
/// the comparison with the original, and the file.
struct DevelopPhotoMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle("Show Original", isOn: $model.showsOriginal)
            .disabled(model.original == nil)
        Divider()
        Button("Copy Adjustments") { model.copyAdjustments() }
            .disabled(!model.canCopyAdjustments)
        Button("Paste Adjustments") { model.pasteAdjustments() }
            .disabled(!model.canPasteAdjustments)
        Button("Reset Adjustments") { model.resetAdjustments() }
            .disabled(!model.hasPhoto)
        Button("Crop and Straighten") { model.beginCrop() }
            .disabled(!model.canCrop || model.isCropping)
        Divider()
        Button("Export…") { model.presentExport() }
            .disabled(!model.canPresentExport)
        if let photo = model.selection?.url {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([photo]) }
        }
    }
}

/// A new tag for photos: its name, and its color as the Finder offers it. A name a tag already
/// has puts that tag on, with its own color.
private struct NewTagSheet: View {
    @Environment(AppModel.self) private var model
    /// The photos the tag is put on.
    let photos: [URL]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: FinderTagColor?

    var body: some View {
        let isNamed = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        FormSheet(
            Text("New Tag"),
            message: photos.count == 1
                ? Text("The tag is put on “\(photos[0].lastPathComponent)”, as in the Finder.")
                : Text("The tag is put on the selected photos, as in the Finder."),
            confirm: SheetAction(Text("Add"), isEnabled: isNamed) {
                model.addTag(named: name, color: color, to: photos)
                dismiss()
            },
            cancel: SheetAction(Text("Cancel")) { dismiss() },
        ) {
            TextField("Name", text: $name)
            LabeledContent("Color") {
                TagColorPicker(color: $color)
            }
        }
    }
}
