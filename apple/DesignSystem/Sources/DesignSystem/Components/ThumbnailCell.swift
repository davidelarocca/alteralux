import SwiftUI

/// A photo thumbnail for a strip or grid, with a selection outline.
///
/// In a strip every thumbnail has the same size and the photo fills it, cropped. A grid gives
/// the size and asks for the whole photo, so an upright one is not cut.
///
/// It only draws: wrap it in a `Button` to make it selectable.
public struct ThumbnailCell: View {
    /// The size every thumbnail is drawn at, in points.
    public static let size = CGSize(width: 84, height: 56)

    private let image: CGImage?
    private let isSelected: Bool
    private let size: CGSize
    private let showsWholePhoto: Bool

    /// - Parameters:
    ///   - image: `nil` shows a placeholder while the thumbnail loads.
    ///   - size: the size it is drawn at, in points.
    ///   - showsWholePhoto: fit the whole photo in the cell instead of filling it.
    public init(
        image: CGImage?, isSelected: Bool, size: CGSize = ThumbnailCell.size, showsWholePhoto: Bool = false,
    ) {
        self.image = image
        self.isSelected = isSelected
        self.size = size
        self.showsWholePhoto = showsWholePhoto
    }

    public var body: some View {
        ZStack {
            Color.DS.thumbnailPlaceholder
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: showsWholePhoto ? .fit : .fill)
            }
        }
        .frame(width: size.width, height: size.height)
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
        ThumbnailCell(image: nil, isSelected: false, size: CGSize(width: 160, height: 120), showsWholePhoto: true)
        ThumbnailCell(image: nil, isSelected: true, size: CGSize(width: 160, height: 120), showsWholePhoto: true)
    }
    .padding(Spacing.l)
}
