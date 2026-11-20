import SwiftUI

/// One button of a sheet: its title, what it does, and whether it can be pressed now.
public struct SheetAction {
    let title: Text
    let isEnabled: Bool
    let action: () -> Void

    public init(_ title: Text, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// The one shape of a sheet of the app, drawn after the system's alert so that a question the
/// system asks and one the app asks look alike: a title in bold, a line of explanation, the
/// system's grouped form, and wide round buttons side by side, the default one last.
///
/// Return presses the default button, Escape the other.
public struct FormSheet<Content: View>: View {
    private let title: Text
    private let message: Text?
    private let confirm: SheetAction?
    private let cancel: SheetAction
    private let content: Content

    /// - Parameters:
    ///   - title: what the sheet is for, as an alert would say it.
    ///   - message: a line that explains, when the title is not enough.
    ///   - confirm: the default button. `nil` for a sheet that only shows something going on.
    ///   - cancel: the button that leaves without doing it, or stops what is going on.
    ///   - content: the rows of the form, in `Section`s when they need a note under them.
    public init(
        _ title: Text, message: Text? = nil, confirm: SheetAction?, cancel: SheetAction,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.message = message
        self.confirm = confirm
        self.cancel = cancel
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                title
                    .font(Typography.sheetTitle)
                message
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            Form {
                content
            }
            .formStyle(.grouped)
            buttons
        }
        .frame(width: SheetSize.width)
    }

    private var buttons: some View {
        HStack(spacing: Spacing.s) {
            Button(role: .cancel, action: cancel.action) {
                cancel.title.frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.cancelAction)
            .disabled(!cancel.isEnabled)
            if let confirm {
                Button(action: confirm.action) {
                    confirm.title.frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!confirm.isEnabled)
            }
        }
        .lineLimit(1)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.l)
    }
}

#Preview("Form sheet, options") {
    FormSheet(
        Text("Export 340 Photos"),
        confirm: SheetAction(Text("Export")) {},
        cancel: SheetAction(Text("Cancel")) {},
    ) {
        Picker("Format", selection: .constant(0)) {
            Text("JPEG").tag(0)
        }
        Toggle("Include camera metadata", isOn: .constant(true))
    }
}

#Preview("Form sheet, a message and a default button that waits") {
    FormSheet(
        Text("Save as New Recipe"),
        message: Text("The recipe keeps the look of this photo: everything but its white balance."),
        confirm: SheetAction(Text("Save"), isEnabled: false) {},
        cancel: SheetAction(Text("Cancel")) {},
    ) {
        TextField("Name", text: .constant(""))
    }
}

#Preview("Form sheet, something going on") {
    FormSheet(Text("Developing"), confirm: nil, cancel: SheetAction(Text("Stop")) {}) {
        ProgressView(value: 0.35) {
            Text("120 of 340 · DSC_4836.NEF")
        }
    }
}

#Preview("Form sheet, long text, dark") {
    FormSheet(
        Text("A title long enough to need a second line in a sheet as narrow as this one is"),
        message: Text("A message that explains at some length what is about to happen, and wraps."),
        confirm: SheetAction(Text("A long default button")) {},
        cancel: SheetAction(Text("A long way out")) {},
    ) {
        Toggle("An option with a long title that has to fit beside its switch", isOn: .constant(false))
    }
    .preferredColorScheme(.dark)
}
