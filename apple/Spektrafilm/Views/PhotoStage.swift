import SwiftUI

/// Shows the selected photo on a neutral dark surround, or the empty state.
struct PhotoStage: View {
    @Environment(AppModel.self) private var model

    /// A fixed neutral grey: colors are judged against the same surround in
    /// light and dark appearance.
    private static let surround = Color(white: 0.11)

    /// The developed photo, or the original while comparing.
    private var displayedImage: CGImage? {
        if model.showsOriginal, let original = model.original { return original }
        return model.preview?.cgImage
    }

    var body: some View {
        ZStack {
            Self.surround.ignoresSafeArea()

            if let image = displayedImage, let loaded = model.loaded {
                ZoomableImageView(
                    image: image,
                    pixelSize: CGSize(width: loaded.width, height: loaded.height),
                    command: model.zoomCommand,
                    commandID: model.zoomRequestID,
                    onScaleChange: { model.viewerDidChange(scale: $0) }
                )
                .accessibilityLabel(
                    model.showsOriginal ? Text("Original photo") : Text("Developed photo"))
            } else if model.hasPhoto || model.isLoading || model.isStarting {
                ProgressView()
                    .controlSize(.large)
                    .environment(\.colorScheme, .dark)
            } else {
                ContentUnavailableView {
                    Label("Open a Photo", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Drag RAW files here, or choose Open.")
                } actions: {
                    Button("Open…") { model.isImporterPresented = true }
                        .buttonStyle(.borderedProminent)
                }
                .environment(\.colorScheme, .dark)
            }
        }
        .overlay(alignment: .topLeading) {
            if model.showsOriginal, model.original != nil {
                Text("Original")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: .capsule)
                    .padding(12)
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
