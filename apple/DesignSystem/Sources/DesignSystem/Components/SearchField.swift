import AppKit
import SwiftUI

/// The system's search field: a magnifying glass, the prompt, and a button that clears what was
/// typed. It is `NSSearchField` itself, so it looks and behaves as macOS draws it everywhere.
///
/// It takes the keyboard when it appears, for a list that is searched as soon as it opens. The
/// up and down arrows and Return are passed on, so the list under it can be moved through and
/// chosen from without leaving the field. Escape clears the text first; with nothing typed it
/// goes on to whatever holds the field (a popover closes).
public struct SearchField: View {
    private let label: String
    private let prompt: String
    @Binding private var text: String
    private let onMove: ((Int) -> Void)?
    private let onSubmit: (() -> Void)?

    /// - Parameters:
    ///   - label: what assistive technologies read ("Search films"), already localized.
    ///   - prompt: shown in the empty field ("Search"), already localized.
    ///   - onMove: called with -1 for the up arrow and 1 for the down arrow.
    ///   - onSubmit: called on Return.
    public init(
        _ label: String,
        prompt: String,
        text: Binding<String>,
        onMove: ((Int) -> Void)? = nil,
        onSubmit: (() -> Void)? = nil,
    ) {
        self.label = label
        self.prompt = prompt
        _text = text
        self.onMove = onMove
        self.onSubmit = onSubmit
    }

    public var body: some View {
        SystemSearchField(label: label, prompt: prompt, text: $text, onMove: onMove, onSubmit: onSubmit)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SystemSearchField: NSViewRepresentable {
    let label: String
    let prompt: String
    @Binding var text: String
    let onMove: ((Int) -> Void)?
    let onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> FocusingSearchField {
        let field = FocusingSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusingSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = prompt
        field.setAccessibilityLabel(label)
        field.isEnabled = context.environment.isEnabled
        field.controlSize = context.environment.controlSize.appKit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SystemSearchField

        init(parent: SystemSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                guard let onMove = parent.onMove else { return false }
                onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard let onMove = parent.onMove else { return false }
                onMove(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                guard let onSubmit = parent.onSubmit else { return false }
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // With text, Escape clears it; with none, it goes on and closes what holds the field.
                guard !parent.text.isEmpty else { return false }
                parent.text = ""
                return true
            default:
                return false
            }
        }
    }
}

/// A search field that takes the keyboard once it is in a window.
final class FocusingSearchField: NSSearchField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // The window makes it first responder after SwiftUI has finished placing it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}

private extension ControlSize {
    var appKit: NSControl.ControlSize {
        switch self {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
    }
}

#Preview("Search fields") {
    @Previewable @State var empty = ""
    @Previewable @State var typed = "Portra"

    VStack(alignment: .leading, spacing: Spacing.l) {
        SearchField("Search films", prompt: "Search", text: $empty)
        SearchField("Search films", prompt: "Search", text: $typed)
        SearchField(
            "Search films", prompt: "A long prompt that has more words than the field has room for", text: $empty,
        )
        SearchField("Search films", prompt: "Search", text: $typed)
            .disabled(true)
    }
    .padding(Spacing.l)
    .frame(width: 300)
}
