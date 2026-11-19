import SwiftUI

/// Every component of the design system in every state: the visual inventory.
/// Shown from Xcode previews; not meant for reuse in the app.
public struct GalleryView: View {
    @State private var exposure = 0.3
    @State private var filter = -12.0

    public init() {}

    public var body: some View {
        Form {
            Section("ParameterSlider") {
                ParameterSlider("Exposure", value: $exposure, in: -5 ... 5, step: 0.1, fractionDigits: 1, showsSign: true)
                ParameterSlider("Yellow filter", value: $filter, in: -50 ... 50, step: 1, fractionDigits: 0, showsSign: true)
            }
            Section("ThumbnailCell") {
                HStack(spacing: Spacing.s) {
                    ThumbnailCell(image: nil, isSelected: false)
                    ThumbnailCell(image: nil, isSelected: true)
                }
            }
            Section("StatusBadge") {
                StatusBadge("Original")
            }
            Section("Colors") {
                swatch("viewerSurround", Color.DS.viewerSurround)
                swatch("thumbnailPlaceholder", Color.DS.thumbnailPlaceholder)
                swatch("hairline", Color.DS.hairline)
            }
        }
        .formStyle(.grouped)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        LabeledContent(name) {
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(color)
                .frame(width: ThumbnailCell.size.width, height: Spacing.xl)
        }
    }
}

#Preview("Gallery") {
    GalleryView()
        .frame(width: 420, height: 560)
}
