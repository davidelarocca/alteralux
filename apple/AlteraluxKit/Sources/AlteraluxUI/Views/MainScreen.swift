import DesignSystem
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
            // The system's controls, in gray: nothing saturated sits next to the photo.
            .tint(Color.DS.controlTint)
            .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

/// The main screen: the photo, with the zoom and the strip of open photos below it, and the
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
                ZoomControls()
                Divider()
                FilmstripView()
            }
        }
        .inspector(isPresented: $showsInspector) {
            InspectorView()
                .inspectorColumnWidth(
                    min: InspectorWidth.minimum, ideal: InspectorWidth.ideal, max: InspectorWidth.maximum,
                )
        }
        .navigationTitle(model.selection?.name ?? "alteralux")
        .navigationSubtitle(model.materialsSummary)
        // The toolbar shows the photo's name itself, between previous and next.
        .toolbar(removing: .title)
        .toolbar {
            MainToolbar(model: model, showsInspector: $showsInspector)
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
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.open(urls)
            return true
        }
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
            set: {
                if !$0 {
                    model.alertMessage = nil
                }
            },
        )
    }
}

/// The toolbar of the main window: on the leading side open, then previous and next around the
/// photo's name; on the trailing side compare, export and the inspector.
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

        if model.hasPhoto {
            ToolbarSpacer(.fixed, placement: .navigation)
            ToolbarItem(placement: .navigation) {
                PhotoTitle(model: model)
            }
        }

        // The title's place is taken by the photo's name: the actions stay on the trailing side.
        ToolbarSpacer(.flexible)

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $model.showsOriginal) {
                Label("Original", systemImage: "circle.lefthalf.filled")
            }
            .help("Compare with the original")
            .disabled(model.original == nil)

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

/// The selected photo in the toolbar: its name over the film and paper it is developed with,
/// between the buttons for the previous and the next photo of the strip.
private struct PhotoTitle: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            step(-1, title: "Previous Photo", systemImage: "chevron.backward")
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: model.selection?.name ?? "")
                    .font(Typography.title)
                Text(verbatim: model.materialsSummary)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            step(1, title: "Next Photo", systemImage: "chevron.forward")
        }
    }

    private func step(_ offset: Int, title: LocalizedStringKey, systemImage: String) -> some View {
        Button {
            model.selectAdjacent(offset: offset)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(title)
        .disabled(!model.canSelectAdjacent(offset: offset))
    }
}
