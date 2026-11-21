import SwiftUI

/// A few related controls on one round-ended piece of the system's glass, the way the toolbar
/// groups its buttons (undo and redo, crop and compare).
///
/// It floats over what is under it. Its controls are the system's; its buttons have no border, the
/// glass being their only background, and their titles are white so they read as buttons, dimmed
/// when disabled and while pressed. A button that stands alone uses the system's
/// `.glass` or `.glassProminent` button style instead. Put the groups of one bar in a
/// `GlassEffectContainer`, so the glass of each is drawn as one material.
public struct GlassGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            content
        }
        // Not `.borderless`: it writes every title in gray, which on glass reads as disabled.
        .buttonStyle(GlassGroupButtonStyle())
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: Self.minimumHeight)
        .glassEffect(.regular, in: .capsule)
    }

    /// As tall as a large glass button, so a group and a button beside it line up.
    private static var minimumHeight: CGFloat {
        34
    }
}

/// A button inside a `GlassGroup`: its title alone, white, dimmed when it is disabled and while
/// it is pressed.
struct GlassGroupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Title(configuration: configuration)
    }

    private struct Title: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .opacity(configuration.isPressed ? GlassGroupButtonStyle.pressedOpacity : 1)
                .contentShape(.rect)
        }
    }

    /// How much of a title shows while it is pressed.
    static var pressedOpacity: Double {
        0.5
    }
}

#Preview("Glass groups") {
    @Previewable @State var value = 1.5
    @Previewable @State var upright = false

    GlassEffectContainer(spacing: Spacing.m) {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(spacing: Spacing.m) {
                GlassGroup {
                    Button("Rotate Left", systemImage: "rotate.left") {}
                    Button("Flip Horizontally", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {}
                }
                .labelStyle(.iconOnly)
                GlassGroup {
                    Picker("Orientation", selection: $upright) {
                        Label("Landscape", systemImage: "rectangle").tag(false)
                        Label("Portrait", systemImage: "rectangle.portrait").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .labelsHidden()
                    .fixedSize()
                }
                Button("Cancel") {}
                    .buttonStyle(.glass)
                Button("Done") {}
                    .buttonStyle(.glassProminent)
            }
            GlassGroup {
                ParameterSlider("Straighten", value: $value, in: -45 ... 45, step: 0.1, fractionDigits: 1)
                    .frame(width: 200)
            }
            GlassGroup {
                Button("A group with a long title") {}
                Button("Disabled") {}
                    .disabled(true)
            }
        }
        .controlSize(.large)
    }
    .padding(Spacing.xl)
    .background(Color.DS.viewerSurround)
}
