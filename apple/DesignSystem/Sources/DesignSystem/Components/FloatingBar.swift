import SwiftUI

/// A bar of actions that floats over content, near its bottom edge: a round-ended panel of the
/// system's material with a soft shadow, as wide as what it holds.
///
/// It appears for what is selected and goes when nothing is: the content under it stays in
/// sight around it. Its buttons and menus are the system's, drawn round like the bar.
public struct FloatingBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            content
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .menuStyle(.button)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        // The bar's own background, not a material: over a material the round buttons lose
        // their fill and read as plain text.
        .background(.bar, in: .capsule)
        .overlay {
            Capsule().strokeBorder(Color.DS.hairline, lineWidth: Self.lineWidth)
        }
        .shadow(color: .black.opacity(Self.shadowOpacity), radius: Self.shadowRadius, y: Self.shadowOffset)
    }

    private static var lineWidth: CGFloat {
        1
    }

    private static var shadowOpacity: Double {
        0.35
    }

    private static var shadowRadius: CGFloat {
        14
    }

    private static var shadowOffset: CGFloat {
        6
    }
}

#Preview("Floating bar") {
    VStack(spacing: Spacing.xl) {
        FloatingBar {
            Text("3 photos")
                .font(Typography.value)
            Divider()
            Menu("Recipe") {}
            Button("Export…") {}
            Button("Discard") {}
        }
        FloatingBar {
            Text("A selection with a long description of what it holds")
            Button("One Action With a Long Title") {}
                .disabled(true)
        }
    }
    .fixedSize()
    .padding(Spacing.xl)
    .background(Color.DS.viewerSurround)
}
