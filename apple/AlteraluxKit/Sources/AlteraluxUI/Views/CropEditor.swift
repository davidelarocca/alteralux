import AlteraluxKit
import DesignSystem
import SwiftUI

/// The whole photo, developed and turned by the straightening, with the frame being chosen over
/// it. The frame takes the drags; the model keeps it in the turned photo.
struct CropEditor: View {
    @Environment(AppModel.self) private var model
    /// The whole photo, developed.
    let image: CGImage
    let session: CropSession

    var body: some View {
        GeometryReader { proxy in
            let photo = Self.photoRect(of: session.photo, in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: photo.width, height: photo.height)
                    .rotationEffect(.degrees(session.angle))
                    .position(x: photo.midX, y: photo.midY)
                    .accessibilityLabel(Text("Photo being cropped"))
                CropFrame(
                    rect: Self.frameRect(of: session.crop, on: photo),
                    onDrag: { grip, translation in
                        model.dragCrop(
                            PhotoCrop.Handle(horizontal: grip.horizontal, vertical: grip.vertical),
                            by: CGSize(
                                width: translation.width / photo.width,
                                height: translation.height / photo.height,
                            ),
                        )
                    },
                    onDragEnd: { model.endCropDrag() },
                )
            }
        }
        .clipped()
    }

    /// Where the whole photo is drawn: as large as it fits, with room around it.
    static func photoRect(of photo: CGSize, in container: CGSize) -> CGRect {
        let room = CGSize(
            width: max(1, container.width - 2 * Spacing.xl),
            height: max(1, container.height - 2 * Spacing.xl),
        )
        let scale = min(room.width / photo.width, room.height / photo.height)
        let size = CGSize(width: photo.width * scale, height: photo.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
            width: size.width, height: size.height,
        )
    }

    /// The frame on the photo drawn at `photo`.
    static func frameRect(of crop: PhotoCrop, on photo: CGRect) -> CGRect {
        CGRect(
            x: photo.minX + crop.left * photo.width, y: photo.minY + crop.top * photo.height,
            width: crop.width * photo.width, height: crop.height * photo.height,
        )
    }
}
