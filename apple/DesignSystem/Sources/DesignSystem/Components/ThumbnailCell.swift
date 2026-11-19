import SwiftUI

/// A photo thumbnail for a strip or grid, with a selection outline.
///
/// It only draws: wrap it in a `Button` to make it selectable.
public struct ThumbnailCell: View {
    /// The size every thumbnail is drawn at, in points.
    public static let size = CGSize(width: 84, height: 56)

    private let image: CGImage?
    private let isSelected: Bool

    /// - Parameter image: `nil` shows a placeholder while the thumbnail loads.
    public init(image: CGImage?, isSelected: Bool) {
        self.image = image
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Color.DS.thumbnailPlaceholder
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(.rect(cornerRadius: Radius.thumbnail))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.thumbnail)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.DS.hairline,
                    lineWidth: isSelected ? Self.selectedLineWidth : Self.lineWidth,
                )
        }
    }

    private static let lineWidth: CGFloat = 1
    private static let selectedLineWidth: CGFloat = 2
}

#Preview("Thumbnail cells") {
    HStack(spacing: Spacing.s) {
        ThumbnailCell(image: nil, isSelected: false)
        ThumbnailCell(image: nil, isSelected: true)
    }
    .padding(Spacing.l)
}
