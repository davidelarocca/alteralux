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

/// The main screen: the photo with the strip of open photos below it, and the
/// adjustments in an inspector on the right.
struct MainScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showsInspector = true

    /// Width of the adjustments inspector, in points.
    private enum InspectorWidth {
        static let minimum: CGFloat = 280
        static let ideal: CGFloat = 320
        static let maximum: CGFloat = 440
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            PhotoStage()
            if !model.photos.isEmpty {
                Divider()
                FilmstripView()
            }
        }
        .inspector(isPresented: $showsInspector) {
            InspectorView()
                .inspectorColumnWidth(
                    min: InspectorWidth.minimum, ideal: InspectorWidth.ideal, max: InspectorWidth.maximum)
        }
        .navigationTitle(model.selection?.name ?? "spektrafilm")
        .navigationSubtitle(model.materialsSummary)
        .toolbar {
            MainToolbar(model: model, showsInspector: $showsInspector)
        }
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: AppModel.openableTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.open(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.open(urls)
            return true
        }
        .onOpenURL { model.open([$0]) }
        .onChange(of: model.settings) { model.settingsDidChange() }
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
            set: { if !$0 { model.alertMessage = nil } }
        )
    }
}

/// The toolbar of the main window: open, compare, zoom, export, inspector.
private struct MainToolbar: ToolbarContent {
    @Bindable var model: AppModel
    @Binding var showsInspector: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.isImporterPresented = true
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .help("Open photos")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $model.showsOriginal) {
                Label("Original", systemImage: "circle.lefthalf.filled")
            }
            .help("Compare with the original")
            .disabled(model.original == nil)

            ControlGroup {
                Button("Fit") { model.zoom(.fit) }
                    .help("Zoom to fit")
                Button("100%") { model.zoom(.actualSize) }
                    .help("Actual size")
            }
            .disabled(model.loaded == nil)

            Button {
                model.isExportPresented = true
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .help("Export the developed photo")
            .disabled(!model.canExport)

            Button {
                showsInspector.toggle()
            } label: {
                Label("Adjustments", systemImage: "slider.horizontal.3")
            }
            .help("Show or hide the adjustments")
        }
    }
}
