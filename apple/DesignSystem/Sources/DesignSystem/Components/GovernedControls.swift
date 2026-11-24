import SwiftUI

public extension EnvironmentValues {
    /// Why the controls here are disabled, when another control governs them: what assistive
    /// technologies read after the title of a `ParameterSlider` or a `WindowPopUp`.
    @Entry var governedReason: LocalizedStringKey?
}

public extension View {
    /// Disables the controls another one governs (the details of a parameter that is switched
    /// off, the sliders an automatic mode sets) and tells assistive technologies why. The reason
    /// is drawn once by the caller, as the note of the group's `InspectorSubheading` or of one
    /// slider; here every slider and pop-up of the group is read with it.
    func governed(_ isGoverned: Bool, reason: LocalizedStringKey) -> some View {
        disabled(isGoverned)
            .environment(\.governedReason, isGoverned ? reason : nil)
    }
}
