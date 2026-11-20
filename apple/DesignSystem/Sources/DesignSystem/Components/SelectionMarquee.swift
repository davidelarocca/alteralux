import SwiftUI

/// The rectangle drawn while the pointer is dragged over a grid to select what it covers, as
/// the Finder draws it: a light veil with a thin edge, over the content and in the way of
/// nothing. It is drawn for the surround of the photos, which is dark in either appearance.
public struct SelectionMarquee: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(Self.fillOpacity))
            .overlay {
                Rectangle().strokeBorder(Color.white.opacity(Self.edgeOpacity), lineWidth: Self.lineWidth)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static var fillOpacity: Double {
        0.12
    }

    private static var edgeOpacity: Double {
        0.4
    }

    private static var lineWidth: CGFloat {
        1
    }
}

#Preview("Selection marquee") {
    ZStack(alignment: .topLeading) {
        HStack(spacing: Spacing.m) {
            ForEach(0 ..< 3) { _ in
                RoundedRectangle(cornerRadius: Radius.thumbnail)
                    .fill(Color.DS.thumbnailPlaceholder)
                    .frame(width: 90, height: 60)
            }
        }
        SelectionMarquee()
            .frame(width: 150, height: 80)
            .offset(x: 40, y: 20)
    }
    .padding(Spacing.xl)
    .background(Color.DS.viewerSurround)
}
