import DesignSystem
import SwiftUI

/// Shows the selected photo on a neutral dark surround, or the empty state.
struct PhotoStage: View {
    @Environment(AppModel.self) private var model

    /// The developed photo, or the original while comparing.
    private var displayedImage: CGImage? {
        if model.showsOriginal, let original = model.original {
            return original
        }
        return model.preview?.cgImage
    }

    var body: some View {
        ZStack {
            // A fixed neutral grey to judge colors against.
            Color.DS.viewerSurround.ignoresSafeArea()

            if let image = displayedImage, let loaded = model.loaded {
                ZoomableImageView(
                    image: image,
                    pixelSize: CGSize(width: loaded.width, height: loaded.height),
                    command: model.zoomCommand,
                    commandID: model.zoomRequestID,
                    onScaleChange: { model.viewerDidChange(scale: $0) },
                )
                .accessibilityLabel(
                    model.showsOriginal ? Text("Original photo") : Text("Developed photo"),
                )
            } else if model.hasPhoto || model.isLoading || model.isStarting {
                ProgressView()
                    .controlSize(.large)
            } else {
                ContentUnavailableView {
                    Label("Open a Photo", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Drag RAW files here, or choose Open.")
                } actions: {
                    Button("Open…") { model.isImporterPresented = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if model.showsOriginal, model.original != nil {
                StatusBadge("Original")
                    .padding(Spacing.m)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.isRendering || model.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .padding(Spacing.m)
            }
        }
    }
}
