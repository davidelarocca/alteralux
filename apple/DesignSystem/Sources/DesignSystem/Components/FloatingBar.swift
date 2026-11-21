import SwiftUI

/// A bar of actions that floats over content, near its bottom edge: a `GlassGroup`, one
/// round-ended piece of the system's glass as wide as what it holds.
///
/// It appears for what is selected and goes when nothing is: the content under it stays in
/// sight around it, and through it. Its buttons and menus are the system's.
public struct FloatingBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer {
            GlassGroup {
                content
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .controlSize(.large)
    }
}

#Preview("Floating bar") {
    VStack(spacing: Spacing.xl) {
        FloatingBar {
            Text("3 photos")
                .font(Typography.value)
            Divider()
            ChoiceListButton(Text("Recipe"), choices: [], empty: Text("No recipes"))
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
