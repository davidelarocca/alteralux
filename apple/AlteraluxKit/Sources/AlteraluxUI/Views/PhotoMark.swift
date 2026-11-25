import AlteraluxKit
import DesignSystem
import SwiftUI

/// A small mark in a corner of a photo's thumbnail, saying something of the photo at a glance:
/// that it has adjustments, that it is discarded. The same in the library's grid and in the
/// strip. It says nothing to assistive technologies: the thumbnail's own label does.
struct PhotoMark: View {
    /// The mark of a photo that has adjustments kept with it.
    static let adjusted = PhotoMark("slider.horizontal.3")
    /// The mark of a discarded photo.
    static let discarded = PhotoMark("xmark")

    private let symbol: String

    private init(_ symbol: String) {
        self.symbol = symbol
    }

    var body: some View {
        Image(systemName: symbol)
            .font(Typography.badge)
            .padding(Spacing.xs)
            .background(.regularMaterial, in: .rect(cornerRadius: Radius.control))
            .padding(Spacing.xs)
            .accessibilityHidden(true)
    }
}

/// A photo's colored Finder tags as a mark in a corner of its thumbnail: a dot for each, three
/// at most, as the Finder shows them. For the strip, which has no line under its thumbnails
/// where the grid draws them. Nothing for a photo without a colored tag.
struct TagMark: View {
    private let dots: TagDots

    init(_ tags: [FinderTag]) {
        dots = TagDots(tags, limit: 3)
    }

    var body: some View {
        if !dots.isEmpty {
            dots
                .padding(Spacing.xs)
                .background(.regularMaterial, in: .capsule)
                .padding(Spacing.xs)
        }
    }
}

#Preview("On a thumbnail") {
    HStack(spacing: Spacing.m) {
        ThumbnailCell(image: nil, isSelected: false)
            .overlay(alignment: .bottomTrailing) { PhotoMark.adjusted }
        ThumbnailCell(image: nil, isSelected: true)
            .overlay(alignment: .bottomLeading) { PhotoMark.discarded }
        ThumbnailCell(image: nil, isSelected: false)
            .overlay(alignment: .topLeading) {
                TagMark([FinderTag(name: "Red", color: .red), FinderTag(name: "Blue", color: .blue)])
            }
            .overlay(alignment: .bottomTrailing) { PhotoMark.adjusted }
            .overlay(alignment: .bottomLeading) { PhotoMark.discarded }
    }
    .padding()
}
