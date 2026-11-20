import SwiftUI

/// The heading of a pane, which opens the list to change what the pane is about: the film at
/// the top of the inspector. A line of context sits above the name.
///
/// It draws no ground of its own: it is a row of the form or list it is placed in.
public struct HeadingButton: View {
    private let caption: Text
    private let title: String
    private let action: () -> Void

    /// - Parameters:
    ///   - caption: what kind of thing the title names ("Film · color negative · ISO 400").
    ///   - title: a name, shown as it is.
    public init(caption: Text, title: String, action: @escaping () -> Void) {
        self.caption = caption
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    caption
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(verbatim: title)
                        .font(Typography.heading)
                        .lineLimit(1)
                        .minimumScaleFactor(Self.smallestTitleScale)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The mark of a pop-up choice, as on the system's pop-up buttons.
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// A long film name shrinks a little before it is cut.
    private static let smallestTitleScale = 0.8
}

#Preview("Heading buttons") {
    Form {
        HeadingButton(caption: Text("Film · color negative · ISO 400"), title: "Kodak Portra 400") {}
        HeadingButton(
            caption: Text("Film · black and white · ISO 250"), title: "Kodak Double-X Negative Film 5222",
        ) {}
    }
    .formStyle(.grouped)
    .frame(width: 320)
}
