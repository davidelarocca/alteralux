import AlteraluxKit
import DesignSystem
import SwiftUI

/// A dot for each colored Finder tag of a photo, as the Finder draws them beside a name. They say
/// nothing to assistive technologies: the photo's own element says its tags.
struct TagDots: View {
    private let colors: [FinderTagColor]

    /// The diameter of a dot, in points.
    private static let dotSize: CGFloat = 8

    /// - Parameter limit: how many dots at most, where there is little room; `nil` for all.
    init(_ tags: [FinderTag], limit: Int? = nil) {
        let colors = tags.compactMap(\.color)
        self.colors = limit.map { Array(colors.prefix($0)) } ?? colors
    }

    /// Whether there is a dot to draw: a photo's tags may all be without a color.
    var isEmpty: Bool {
        colors.isEmpty
    }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.swatch)
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Beside a name") {
    HStack(spacing: Spacing.xs) {
        TagDots([FinderTag(name: "Red", color: .red), FinderTag(name: "Blue", color: .blue), FinderTag(name: "Plain")])
        Text(verbatim: "IMG_0042.dng")
    }
    .padding()
}
