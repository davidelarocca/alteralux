import AlteraluxKit
import AppKit
import DesignSystem
import SwiftUI

/// What a photo's menu asks before it acts: a name, with the system's alert.
enum PhotoQuestion: Equatable {
    /// The name of a new tag for the selected photos.
    case newTag
    /// A new name for this photo.
    case rename(URL)
    /// Whether to move the selected photos to the Trash: one click must not empty a folder.
    case trash
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
        ShareLink(items: targets)
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
        tagMenu
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
        Button { act { ask(.trash) } } label: {
            count > 1 ? Text("Move \(count) Photos to Trash") : Text("Move to Trash")
        }
    }

    /// The tags, as the Finder lists them, each with its dot and a check when every photo
    /// carries it: choosing one puts it on or takes it off. Under them, a new tag by its name.
    private var tagMenu: some View {
        let choices = model.tagChoices(for: targets)
        let count = targets.count
        return Menu("Tags") {
            ForEach(choices, id: \.name) { choice in
                Toggle(isOn: Binding(
                    get: { choice.carriedBy == count },
                    set: { _ in act { model.toggleTag(choice.name, color: choice.color) } },
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
            Button("New Tag…") { act { ask(.newTag) } }
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

/// What a photo's menu asks before it acts: a new tag for the selection, with its name and color,
/// in a sheet; a new name for a photo, in the system's alert; whether to move the selected photos
/// to the Trash, in the system's confirmation. The field starts with the photo's
/// name, its extension left out: it stays.
struct PhotoQuestionAlerts: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var question: PhotoQuestion?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isAsking(.newTag)) {
                NewTagSheet()
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
            .confirmationDialog(trashQuestion, isPresented: isAsking(.trash)) {
                Button("Move to Trash", role: .destructive) {
                    Task { await model.trashSelection() }
                }
            } message: {
                if model.selectedPhotos.count == 1 {
                    Text("You can put it back from the Trash in the Finder.")
                } else {
                    Text("You can put them back from the Trash in the Finder.")
                }
            }
            .onChange(of: question) { _, asked in
                if case let .rename(photo) = asked {
                    name = photo.deletingPathExtension().lastPathComponent
                } else {
                    name = ""
                }
            }
    }

    /// The question before the Trash: the photo by its name, or how many.
    private var trashQuestion: Text {
        let photos = model.selectedPhotos
        if photos.count == 1, let photo = photos.first {
            return Text("Move “\(photo.lastPathComponent)” to the Trash?")
        }
        return Text("Move \(photos.count) photos to the Trash?")
    }

    private func isAsking(_ asked: PhotoQuestion) -> Binding<Bool> {
        Binding(get: { question == asked }, set: {
            if !$0 {
                question = nil
            }
        })
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: {
                if case .rename = question {
                    true
                } else {
                    false
                }
            },
            set: {
                if !$0 {
                    question = nil
                }
            },
        )
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

/// A new tag for the selected photos: its name, and its color as the Finder offers it. A name a
/// tag already has puts that tag on, with its own color.
private struct NewTagSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: FinderTagColor?

    var body: some View {
        let isNamed = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        FormSheet(
            Text("New Tag"),
            message: Text("The tag is put on the selected photos, as in the Finder."),
            confirm: SheetAction(Text("Add"), isEnabled: isNamed) {
                model.addTag(named: name, color: color)
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
