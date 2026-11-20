import SwiftUI

/// A titled group of controls in a pane, which the user can collapse: the system's disclosure
/// group, with one addition.
///
/// Collapsed, it shows `summary` beside its title: the values of the controls it hides, so what
/// was set stays in view.
public struct InspectorSection<Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var isExpanded: Bool
    private let summary: String
    private let content: Content

    /// - Parameters:
    ///   - summary: the values of the section's controls, already formatted for the reader
    ///     ("+0.3 · 35 mm"). Shown only while the section is collapsed.
    public init(
        _ title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        summary: String = "",
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.summary = summary
        self.content = content()
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(title)
                    .font(Typography.sectionHeader)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if !isExpanded {
                    Text(verbatim: summary)
                        .font(Typography.value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
