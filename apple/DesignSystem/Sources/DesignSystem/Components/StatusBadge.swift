import SwiftUI

/// A short status label drawn over content, such as "Original" over the photo
/// while comparing. It informs; it is not a control.
public struct StatusBadge: View {
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(Typography.badge)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(.regularMaterial, in: .capsule)
    }
}

#Preview("Status badge") {
    VStack(spacing: Spacing.m) {
        StatusBadge("Original")
        StatusBadge("A longer status that still fits on one line")
    }
    .padding(Spacing.l)
    .background(Color.DS.viewerSurround)
}
