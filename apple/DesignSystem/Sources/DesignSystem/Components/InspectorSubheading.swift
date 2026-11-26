import SwiftUI

/// The title of a group of controls inside a section of a form, naming what they refine ("Grain",
/// "Diffusion filter"), with a line under it when the group does not apply ("Off: switch Grain
/// on to adjust it"). Read as a heading by assistive technologies.
///
/// With a switch on its row, the title is the mode's own: the switch says whether the group
/// takes care of itself ("Exposure … Auto"), and the caller shows the controls under it only
/// while it is off, so the switch is seen to belong to them. A small control of the group's own
/// can stand before the switch (the white balance's dropper).
public struct InspectorSubheading<Accessory: View>: View {
    private let title: LocalizedStringKey
    private let note: LocalizedStringKey?
    private let mode: Mode?
    private let accessory: Accessory

    /// A switch on the title's row.
    private struct Mode {
        let isOn: Binding<Bool>
        /// What is written beside the switch ("Auto").
        let title: LocalizedStringKey
        /// What assistive technologies read for the switch ("Automatic exposure").
        let label: LocalizedStringKey
    }

    /// A title with a switch on its row for the mode that governs the group, and a small control
    /// before the switch.
    ///
    /// - Parameters:
    ///   - isOn: whether the mode is on.
    ///   - switchTitle: the word beside the switch, short ("Auto").
    ///   - switchLabel: the switch as assistive technologies read it, whole ("Automatic exposure").
    ///   - note: a line under the title.
    ///   - accessory: one small control, its symbol alone (a borderless button).
    public init(
        _ title: LocalizedStringKey, isOn: Binding<Bool>, switchTitle: LocalizedStringKey, switchLabel: LocalizedStringKey,
        note: LocalizedStringKey? = nil, @ViewBuilder accessory: () -> Accessory,
    ) {
        self.title = title
        self.note = note
        mode = Mode(isOn: isOn, title: switchTitle, label: switchLabel)
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if let mode {
                HStack(spacing: Spacing.s) {
                    heading
                    Spacer(minLength: Spacing.s)
                    accessory
                    Text(mode.title)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Toggle(mode.label, isOn: mode.isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            } else {
                heading
            }
            if let note {
                Text(note)
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Spacing.s)
        // With a switch the title and the switch are read apart; without, title and note as one.
        .accessibilityElement(children: mode == nil ? .combine : .contain)
    }

    private var heading: some View {
        Text(title)
            .font(Typography.subheading)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

public extension InspectorSubheading where Accessory == EmptyView {
    /// - Parameter note: why the controls under it are disabled, when they are.
    init(_ title: LocalizedStringKey, note: LocalizedStringKey? = nil) {
        self.title = title
        self.note = note
        mode = nil
        accessory = EmptyView()
    }

    /// A title with a switch on its row for the mode that governs the group.
    ///
    /// - Parameters:
    ///   - isOn: whether the mode is on.
    ///   - switchTitle: the word beside the switch, short ("Auto").
    ///   - switchLabel: the switch as assistive technologies read it, whole ("Automatic exposure").
    ///   - note: a line under the title.
    init(
        _ title: LocalizedStringKey, isOn: Binding<Bool>, switchTitle: LocalizedStringKey, switchLabel: LocalizedStringKey,
        note: LocalizedStringKey? = nil,
    ) {
        self.init(title, isOn: isOn, switchTitle: switchTitle, switchLabel: switchLabel, note: note) { EmptyView() }
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

#Preview("With a switch") {
    @Previewable @State var isAutomatic = true
    Form {
        Section {
            InspectorSubheading("Exposure", isOn: $isAutomatic, switchTitle: "Auto", switchLabel: "Automatic exposure")
            if !isAutomatic {
                Toggle("A control it governs", isOn: .constant(true))
            }
            InspectorSubheading(
                "White balance", isOn: .constant(false), switchTitle: "Auto", switchLabel: "Automatic white balance",
            ) {
                Toggle("Pick a gray point", systemImage: "eyedropper", isOn: .constant(false))
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Toggle("A control shown while it is off", isOn: .constant(true))
            InspectorSubheading(
                "A long title for a group of controls with a switch", isOn: .constant(true), switchTitle: "Auto",
                switchLabel: "Automatic mode", note: "A line under it.",
            )
        }
    }
    .formStyle(.grouped)
    .frame(width: 320)
}
