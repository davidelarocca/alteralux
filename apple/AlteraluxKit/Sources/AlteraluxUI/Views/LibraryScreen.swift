import AlteraluxKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// The library: the folders the user added on the left, as they are on disk, and the photos of
/// the one chosen in a grid. A double-click on a photo develops it.
struct LibraryScreen: View {
    @Environment(AppModel.self) private var model

    /// Width of the list of folders, in points.
    private enum SidebarWidth {
        static let minimum: CGFloat = 180
        static let ideal: CGFloat = 220
        static let maximum: CGFloat = 320
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
        .navigationSubtitle(model.library.selectedFolder == nil ? Text(verbatim: "") : Text("\(model.library.photos.count) photos"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Show", selection: $library.filter) {
                    Text("All").tag(LibraryFilter.all)
                    Text("With Adjustments").tag(LibraryFilter.adjusted)
                }
                .pickerStyle(.segmented)
                .help("Choose which photos of the folder are shown")
                .disabled(model.library.selectedFolder == nil)
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
