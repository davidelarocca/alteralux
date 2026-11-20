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

            if let session = model.cropSession {
                // The whole photo, once it is developed whole.
                if let preview = model.preview, model.previewCrop == nil {
                    CropEditor(image: preview.cgImage, session: session)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            } else if let image = displayedImage, let photoSize = model.photoSize {
                ZoomableImageView(
                    image: image,
                    pixelSize: photoSize,
                    command: model.zoomCommand,
                    commandID: model.zoomRequestID,
                    onZoomChange: { model.viewerDidChange($0) },
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
