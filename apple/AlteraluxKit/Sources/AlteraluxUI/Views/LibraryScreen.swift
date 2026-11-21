import AlteraluxKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// The widths of a sidebar: the library's folders, the recipes.
enum SidebarWidth {
    static let minimum: CGFloat = 180
    static let ideal: CGFloat = 220
    static let maximum: CGFloat = 320
}

/// The library: the folders the user added on the left, as they are on disk, and the photos of
/// the one chosen in a grid. A double-click on a photo develops it.
struct LibraryScreen: View {
    @Environment(AppModel.self) private var model

    /// Under the folder's name: how many photos it has, or how many of them the filters show.
    private var subtitle: Text {
        let library = model.library
        guard library.selectedFolder != nil else { return Text(verbatim: "") }
        if library.hasFilters {
            return Text("\(library.visiblePhotos.count) of \(library.filteredCount) photos")
        }
        return Text("\(library.photos.count) photos")
    }

    var body: some View {
        @Bindable var library = model.library
        @Bindable var model = model

        NavigationSplitView {
            LibrarySidebar(isAddingFolder: $model.isFolderImporterPresented)
                .navigationSplitViewColumnWidth(
                    min: SidebarWidth.minimum, ideal: SidebarWidth.ideal, max: SidebarWidth.maximum,
                )
        } detail: {
            LibraryGrid(isAddingFolder: $model.isFolderImporterPresented)
        }
        .navigationTitle(model.library.selectedNode?.name ?? String(localized: "Library"))
        .navigationSubtitle(subtitle)
        .toolbar {
            // In the middle of the toolbar: which photos of the folder are shown.
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $library.filter) {
                    Text("All").tag(LibraryFilter.all)
                    Text("With Adjustments").tag(LibraryFilter.adjusted)
                    Text("Discarded").tag(LibraryFilter.discarded)
                }
                .pickerStyle(.segmented)
                .help("Choose which photos of the folder are shown")
                .disabled(model.library.selectedFolder == nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                LibraryFilterMenu(library: model.library)
            }
        }
        .fileImporter(
            isPresented: $model.isFolderImporterPresented, allowedContentTypes: [.folder],
            allowsMultipleSelection: true,
        ) { result in
            if case let .success(urls) = result {
                model.take(urls)
            }
        }
    }
}

/// The toolbar's Filter and Sort menu: the system's menu, with what the photos are sorted by and
/// which kinds and tags are shown, the option chosen in each group with a checkmark. It sits at
/// the toolbar's trailing edge, so it opens inside the window (`WindowMenuButton`), never past
/// its edge. Its symbol, the system's for filtering, takes the accent color while it hides photos.
private struct LibraryFilterMenu: View {
    let library: LibraryModel

    var body: some View {
        WindowMenuButton(entries: entries) {
            Label("Filter and Sort", systemImage: "line.3.horizontal.decrease")
                // In the accent color while it hides photos.
                .foregroundStyle(library.hasFilters ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .help("Sort the photos of the folder, and choose which kinds and tags are shown")
        .disabled(library.selectedFolder == nil)
    }

    /// The menu, made when it opens: four groups of choices, then clearing the filters.
    private func entries() -> [WindowMenuEntry] {
        let library = library
        var entries: [WindowMenuEntry] = [.heading(String(localized: "Sort By"))]
        let sorts: [(LibrarySort, String)] = [
            (.name, String(localized: "Name")), (.date, String(localized: "Date")), (.kind, String(localized: "Kind")),
        ]
        entries += sorts.map { sort, title in
            .choice(title, isChosen: library.sort == sort) { library.sort = sort }
        }
        entries.append(.heading(String(localized: "Order")))
        entries += [(true, String(localized: "Ascending")), (false, String(localized: "Descending"))].map { ascending, title in
            .choice(title, isChosen: library.sortsAscending == ascending) { library.sortsAscending = ascending }
        }
        entries.append(.heading(String(localized: "Kind of File")))
        let kinds: [(LibraryKinds, String)] = [
            (.all, String(localized: "All Kinds")), (.raw, String(localized: "RAW Only")),
            (.other, String(localized: "All but RAW")),
        ]
        entries += kinds.map { kinds, title in
            .choice(title, isChosen: library.kinds == kinds) { library.kinds = kinds }
        }
        entries.append(.heading(String(localized: "Tag")))
        entries.append(.choice(String(localized: "Any Tag"), isChosen: library.tagFilter == nil) { library.tagFilter = nil })
        entries += library.tagsInFolder.map { tag in
            .choice(tag.name, isChosen: library.tagFilter == tag.name) { library.tagFilter = tag.name }
        }
        entries.append(.separator)
        entries.append(.item(String(localized: "Clear Filters"), isEnabled: library.hasFilters) { library.clearFilters() })
        return entries
    }
}

/// The folders the user added, each with the folders inside it and the number of photos in it.
struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var isAddingFolder: Bool

    var body: some View {
        List(selection: selectedFolder) {
            Section("Folders") {
                ForEach(model.library.roots) { root in
                    if let tree = root.tree {
                        OutlineGroup(tree, children: \.foldersInside) { node in
                            row(node, of: root)
                        }
                    } else {
                        Label(root.folder.url.lastPathComponent, systemImage: "folder.badge.questionmark")
                            .foregroundStyle(.secondary)
                            .help("This folder cannot be reached. It may be on a disk that is not connected.")
                            .contextMenu { removeButton(root) }
                    }
                }
            }
        }
        // Thin scroll bars, as the photo's: wide ones would stay with a mouse.
        .thinScrollBars()
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            Button {
                isAddingFolder = true
            } label: {
                Label("Add Folder…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(Spacing.m)
            .help("Add a folder of photos to the library")
        }
    }

    private func row(_ node: FolderNode, of root: LibraryRoot) -> some View {
        Label(node.name, systemImage: "folder")
            .badge(node.photoCount)
            .contextMenu {
                // Only a folder the user added can be taken out: the ones inside come with it.
                if node.url == root.tree?.url {
                    removeButton(root)
                }
            }
    }

    private func removeButton(_ root: LibraryRoot) -> some View {
        Button("Remove from Library") {
            Task { await model.library.remove(root.id) }
        }
    }

    /// The folder on screen. Choosing a row reads that folder.
    private var selectedFolder: Binding<URL?> {
        Binding(
            get: { model.library.selectedFolder },
            set: { folder in
                if let folder {
                    Task { await model.library.select(folder) }
                }
            },
        )
    }
}

private extension FolderNode {
    /// The folders inside, or `nil` when there are none: a row without a disclosure triangle.
    var foldersInside: [FolderNode]? {
        children.isEmpty ? nil : children
    }
}
