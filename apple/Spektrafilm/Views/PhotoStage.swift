import SwiftUI

/// Shows the developed photo on a neutral dark surround, or the empty state.
struct PhotoStage: View {
    @Environment(AppModel.self) private var model

    /// A fixed neutral grey: colors are judged against the same surround in
    /// light and dark appearance.
    private static let surround = Color(white: 0.11)

    var body: some View {
        ZStack {
            Self.surround.ignoresSafeArea()

            if let preview = model.preview {
                // The CGImage carries its color space, so the system
                // color-manages it for whatever display the window is on.
                Image(preview.cgImage, scale: 1, label: Text("Developed photo"))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(24)
            } else if model.photo != nil || model.isLoading || model.isStarting {
                ProgressView()
                    .controlSize(.large)
                    .environment(\.colorScheme, .dark)
            } else {
                ContentUnavailableView {
                    Label("Open a Photo", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Drag a RAW file here, or choose Open.")
                } actions: {
                    Button("Open…") { model.isImporterPresented = true }
                        .buttonStyle(.borderedProminent)
                }
                .environment(\.colorScheme, .dark)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.isRendering || model.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .environment(\.colorScheme, .dark)
                    .padding(12)
            }
        }
    }
}
