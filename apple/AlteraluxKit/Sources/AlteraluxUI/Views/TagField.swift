import AlteraluxKit
import DesignSystem
import SwiftUI

/// The top of the list of tags, in the Finder's manner: what the tags go on, and a field that
/// narrows the list as one types. A name no tag has yet makes a new tag, with the color chosen
/// under the field; Return puts the tag on the selected photos.
struct TagField: View {
    @Environment(AppModel.self) private var model
    /// What was typed: the list under the field shows the tags whose name holds it.
    @Binding var typed: String
    @State private var color: FinderTagColor?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            title
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            TextField("Tag name", text: $typed, prompt: Text("Find or make a tag"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($isFocused)
                .onSubmit(add)
            if isNew {
                TagColorPicker(color: $color)
            }
        }
        .padding([.horizontal, .top], Spacing.m)
        .padding(.bottom, Spacing.s)
        .animation(Motion.quick, value: isNew)
        .onAppear { isFocused = true }
        .onDisappear {
            typed = ""
            color = nil
        }
    }

    /// What the tags go on: the photo by its name, as the Finder does, or how many photos.
    private var title: Text {
        let selection = model.library.selection
        if selection.count == 1, let photo = selection.first {
            return Text("Assign tags to “\(photo.lastPathComponent)”")
        }
        return Text("Assign tags to \(selection.count) photos")
    }

    private var isNew: Bool {
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.tagChoices.named(typed) == nil
    }

    private func add() {
        model.addTag(named: typed, color: color)
        typed = ""
        color = nil
    }
}

/// The color of a new tag, as the Finder offers it: none, or one of its seven, in a row of dots.
struct TagColorPicker: View {
    @Binding var color: FinderTagColor?

    var body: some View {
        Picker("Color", selection: $color) {
            Image(systemName: "circle")
                .accessibilityLabel(Text("No Color"))
                .tag(FinderTagColor?.none)
            ForEach(FinderTagColor.allCases, id: \.self) { color in
                // A symbol in a palette takes its color only when drawn as a palette.
                Image(systemName: "circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(color.swatch)
                    .accessibilityLabel(Text(color.name))
                    .tag(FinderTagColor?.some(color))
            }
        }
        .pickerStyle(.palette)
        .labelsHidden()
        .help("The color of the new tag")
    }
}
