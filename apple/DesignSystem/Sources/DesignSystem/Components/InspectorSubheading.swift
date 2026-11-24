import SwiftUI

/// The title of a group of controls inside a section of a form, naming what they refine ("Grain",
/// "Diffusion filter"), with a line under it when the group does not apply ("Off: switch Grain
/// on to adjust it"). Read as a heading by assistive technologies.
public struct InspectorSubheading: View {
    private let title: LocalizedStringKey
    private let note: LocalizedStringKey?

    /// - Parameter note: why the controls under it are disabled, when they are.
    public init(_ title: LocalizedStringKey, note: LocalizedStringKey? = nil) {
        self.title = title
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typography.subheading)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if let note {
                Text(note)
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Inspector subheadings") {
    Form {
        Section {
            InspectorSubheading("Grain")
            Toggle("A control under it", isOn: .constant(true))
            InspectorSubheading("Diffusion filter", note: "Off: switch the diffusion filter on to adjust it.")
            Toggle("A disabled control", isOn: .constant(false)).disabled(true)
            InspectorSubheading("A long title for a group of controls, which has to wrap at the inspector's width")
        }
    }
    .formStyle(.grouped)
    .frame(width: 320)
}
