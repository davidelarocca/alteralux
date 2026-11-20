import AlteraluxKit
import DesignSystem
import SwiftUI

/// The top of the list of tags, in the Finder's manner: what the tags go on, and a field to
/// type a tag of one's own, with the color to give it. Return puts it on the selected photos.
struct TagField: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var color: FinderTagColor?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Assign tags to \(model.library.selection.count) photos")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            TextField("New tag", text: $name, prompt: Text("New tag"))
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(add)
            if AppModel.isRecipeName(name) {
                // The color of the new tag: none, or one of the Finder's seven.
                Picker("Color", selection: $color) {
                    Image(systemName: "circle.slash")
                        .accessibilityLabel(Text("No Color"))
                        .tag(FinderTagColor?.none)
                    ForEach(FinderTagColor.allCases, id: \.self) { color in
                        Image(systemName: "circle.fill")
                            .tint(color.swatch)
                            .accessibilityLabel(Text(verbatim: "\(color)"))
                            .tag(FinderTagColor?.some(color))
                    }
                }
                .pickerStyle(.palette)
                .labelsHidden()
            }
        }
        .padding(Spacing.m)
        .onAppear { isFocused = true }
    }

    private func add() {
        model.addTag(named: name, color: color)
        name = ""
        color = nil
    }
}
