import SwiftUI

/// A titled group of controls in a form, which the user can collapse: the system's collapsible
/// section, with one addition.
///
/// Collapsed, it shows `summary` beside its title: the values of the controls it hides, so what
/// was set stays in view. Changed from its defaults (`isModified`), a dot follows its title and,
/// open, a Reset button puts its controls back (`reset`). Place it in a `Form`, as a `Section`.
public struct InspectorSection<Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var isExpanded: Bool
    private let summary: String
    private let isModified: Bool
    private let reset: (() -> Void)?
    private let content: Content

    /// - Parameters:
    ///   - summary: the values of the section's controls, already formatted for the reader
    ///     ("+0.3 · 35 mm"). Shown only while the section is collapsed.
    ///   - isModified: whether its controls differ from their defaults.
    ///   - reset: puts its controls back to their defaults; offered while it is modified and open.
    public init(
        _ title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        summary: String = "",
        isModified: Bool = false,
        reset: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.summary = summary
        self.isModified = isModified
        self.reset = reset
        self.content = content()
    }

    public var body: some View {
        Section(isExpanded: $isExpanded) {
            content
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(title)
                    .lineLimit(1)
                    .layoutPriority(1)
                if isModified {
                    Image(systemName: "circle.fill")
                        .imageScale(.small)
                        .font(Typography.caption)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Changed"))
                }
                Spacer(minLength: 0)
                if !isExpanded {
                    Text(verbatim: summary)
                        .font(Typography.value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if isModified, let reset {
                    Button("Reset", action: reset)
                        .buttonStyle(.borderless)
                        .font(Typography.caption)
                        .help("Puts this section's controls back to how they start")
                }
            }
        }
    }
}

#Preview("Inspector sections") {
    @Previewable @State var isOpen = true
    @Previewable @State var isClosed = false
    @Previewable @State var exposure = 0.3

    Form {
        InspectorSection("Camera", isExpanded: $isOpen, summary: "+0.3 · 35 mm") {
            ParameterSlider("Exposure", value: $exposure, in: -5 ... 5, step: 0.1, fractionDigits: 1, showsSign: true)
        }
        InspectorSection("Print", isExpanded: $isClosed, summary: "1.15 · −12 · 0") {
            ParameterSlider("Print exposure", value: .constant(1.15), in: 0.2 ... 3, defaultValue: 1)
        }
        InspectorSection(
            "A section with a long title", isExpanded: $isClosed,
            summary: "a long summary of many values that cannot all fit",
        ) {
            EmptyView()
        }
    }
    .formStyle(.grouped)
    .frame(width: 320)
}
