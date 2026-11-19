import SwiftUI

/// The main window: the photo, with the adjustments in an inspector.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showsInspector = true

    var body: some View {
        @Bindable var model = model

        PhotoStage()
            .inspector(isPresented: $showsInspector) {
                InspectorView()
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
            }
            .navigationTitle(model.photoName.isEmpty ? "spektrafilm" : model.photoName)
            .navigationSubtitle(model.materialsSummary)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.isImporterPresented = true
                    } label: {
                        Label("Open…", systemImage: "folder")
                    }
                    .help("Open a photo")
                }
                ToolbarItemGroup(placement: .primaryAction) {
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
                allowedContentTypes: AppModel.openableTypes
            ) { result in
                if case .success(let url) = result { model.open(url) }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.open(url)
                return true
            }
            .onOpenURL { model.open($0) }
            .onChange(of: model.settings.filmID) { model.filmDidChange() }
            .onChange(of: model.settings) { model.requestRender() }
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
