import SwiftUI

/// The main window: the photo with the strip of open photos below it, and the
/// adjustments in an inspector on the right.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showsInspector = true

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
                .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
        }
        .navigationTitle(model.selection?.name ?? "spektrafilm")
        .navigationSubtitle(model.materialsSummary)
        .toolbar {
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
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .task { await model.start() }
    }
}
