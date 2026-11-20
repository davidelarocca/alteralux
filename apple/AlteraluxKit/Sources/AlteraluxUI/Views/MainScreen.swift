import SwiftUI

/// The root view of the main window: the main screen plus the window's
/// minimum size (see `docs/LAYOUT_CONTRACT.md`).
public struct MainWindow: View {
    /// The smallest size the window can be resized to, in points.
    public static let minimumSize = CGSize(width: 900, height: 600)
    /// The size of a new window, in points.
    public static let defaultSize = CGSize(width: 1280, height: 820)

    public init() {}

    public var body: some View {
        MainScreen()
            .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

/// The main screen: the library, or the photo being developed.
struct MainScreen: View {
    @Environment(AppModel.self) private var model
    /// The window's undo manager: the one the Edit menu acts on.
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model

        Group {
            if model.showsLibrary {
                LibraryScreen()
            } else {
                DevelopScreen()
            }
        }
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: AppModel.openableTypes,
            allowsMultipleSelection: true,
        ) { result in
            if case let .success(urls) = result {
                model.open(urls)
            }
        }
        // Photos dropped on the window are opened, folders are added to the library.
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.take(urls)
            return true
        }
        .onChange(of: model.settings) { model.settingsDidChange() }
        .onChange(of: undoManager, initial: true) { model.history.undoManager = undoManager }
        .sheet(isPresented: $model.isExportPresented) { ExportSheet() }
        .alert("Something went wrong", isPresented: isAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .task { await model.start() }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: {
                if !$0 {
                    model.alertMessage = nil
                }
            },
        )
    }
}

/// The photo being developed, with the zoom and the strip of photos below it, and the
/// adjustments in an inspector on the right.
struct DevelopScreen: View {
    @Environment(AppModel.self) private var model
    /// A photo opens on its own, the whole window for it; the adjustments are a click away and
    /// stay open from one photo to the next once opened.
    @State private var showsInspector = false
    /// The strip of the photos under the photo, which the View menu hides for more room.
    @AppStorage(DevelopScreen.showsStripKey) private var showsStrip = true
    static let showsStripKey = "develop.showsStrip"

    /// Width of the adjustments inspector, in points.
    private enum InspectorWidth {
        static let minimum: CGFloat = 280
        static let ideal: CGFloat = 320
        static let maximum: CGFloat = 440
    }

    var body: some View {
        VStack(spacing: 0) {
            PhotoStage()
                .contextMenu { DevelopPhotoMenu() }
            if let session = model.cropSession {
                CropControls(session: session)
            } else if !model.photos.isEmpty {
                ZoomControls()
                if showsStrip {
                    Divider()
                    FilmstripView()
                }
            }
        }
        .inspector(isPresented: $showsInspector) {
            InspectorView()
                .inspectorColumnWidth(
                    min: InspectorWidth.minimum, ideal: InspectorWidth.ideal, max: InspectorWidth.maximum,
                )
        }
        // Escape goes back to the library, as in Photos. A sheet or a list over the window
        // takes its own Escape first, and so do the crop controls.
        .background {
            if model.hasLibrary, !model.isCropping {
                Button("Library") { model.showLibrary() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .modifier(HoldToCompare())
        .navigationTitle(model.selection?.name ?? "alteralux")
        .navigationSubtitle(model.materialsSummary)
        .toolbar {
            MainToolbar(model: model, showsInspector: $showsInspector)
        }
    }
}

/// The toolbar while developing: on the leading side the way back to the library (or open, while
/// no folder was added), then previous and next, beside the
/// window's title (the photo's name over its film and paper); on the trailing side undo and
/// redo, then compare, the recipes, export and the inspector.
private struct MainToolbar: ToolbarContent {
    @Bindable var model: AppModel
    @Binding var showsInspector: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if model.hasLibrary {
                Button {
                    model.showLibrary()
                } label: {
                    Label("Library", systemImage: "square.grid.2x2")
                }
                .help("Back to the library")
            } else {
                Button {
                    model.isImporterPresented = true
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                .help("Open photos")
            }
        }

        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.selectAdjacent(offset: -1)
            } label: {
                Label("Previous Photo", systemImage: "chevron.backward")
            }
            .help("Previous Photo")
            .disabled(!model.canSelectAdjacent(offset: -1))

            Button {
                model.selectAdjacent(offset: 1)
            } label: {
                Label("Next Photo", systemImage: "chevron.forward")
            }
            .help("Next Photo")
            .disabled(!model.canSelectAdjacent(offset: 1))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .help("Undo the last change")
            .disabled(!model.canUndo)

            Button {
                model.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .help("Redo the change")
            .disabled(!model.canRedo)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: cropping) {
                Label("Crop", systemImage: "crop")
            }
            .help("Crop and straighten the photo")
            .disabled(!model.canCrop)

            Toggle(isOn: $model.showsOriginal) {
                Label("Original", systemImage: "circle.lefthalf.filled")
            }
            .help("Compare with the original, or hold M")
            .disabled(!model.canCompare)

            RecipeMenu(model: model, savesNew: true) { model.apply($0) }
                .help("Give this photo a recipe, or save its look as one")
                .disabled(!model.hasPhoto)

            Button {
                model.presentExport()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .help("Export the developed photo")
            .disabled(!model.canPresentExport)

            Button {
                showsInspector.toggle()
            } label: {
                Label("Adjustments", systemImage: "slider.horizontal.3")
            }
            .help("Show or hide the adjustments")
        }
    }

    /// On while the crop controls are shown: turned off, it keeps the frame chosen.
    private var cropping: Binding<Bool> {
        Binding(
            get: { model.isCropping },
            set: { $0 ? model.beginCrop() : model.confirmCrop() },
        )
    }
}
