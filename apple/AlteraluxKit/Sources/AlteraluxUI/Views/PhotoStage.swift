import DesignSystem
import SwiftUI

/// Shows the selected photo on a neutral dark surround, or the empty state.
struct PhotoStage: View {
    @Environment(AppModel.self) private var model
    /// Height of the controls under the photo being cropped, which the photo stays above.
    @State private var controlsHeight: CGFloat = 0

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
                // The whole photo, once it is developed whole, with the crop's controls floating
                // over the bottom of the surround and the photo fitting above them.
                Group {
                    if let preview = model.preview, model.previewCrop == nil {
                        CropEditor(image: preview.cgImage, session: session, bottomRoom: controlsHeight)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .overlay(alignment: .bottom) {
                    CropControls(session: session)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
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
        .overlay(alignment: .topTrailing) {
            if model.isRendering || model.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .padding(Spacing.m)
            }
        }
        // The zoom floats over the bottom trailing corner of the photo, on glass.
        .overlay(alignment: .bottomTrailing) {
            if !model.isCropping, displayedImage != nil {
                GlassEffectContainer {
                    ZoomControls()
                }
                .controlSize(.large)
                .padding(Spacing.l)
            }
        }
    }
}
