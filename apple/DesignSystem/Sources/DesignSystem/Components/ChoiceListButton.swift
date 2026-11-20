import SwiftUI

/// One thing to choose in a `ChoiceListButton`.
public struct Choice: Identifiable {
    /// Whether the choice holds for what is selected: for none of it, all of it, or part.
    public enum Mark: Sendable {
        case off, all, part
    }

    public let id: String
    let title: String
    let subtitle: String?
    let color: Color?
    let symbol: String?
    let mark: Mark
    let action: () -> Void

    /// - Parameters:
    ///   - subtitle: a line of context under the title.
    ///   - color: a dot of this color before the title: the color of a tag.
    ///   - symbol: a system symbol before the title, when there is no color.
    public init(
        id: String, title: String, subtitle: String? = nil, color: Color? = nil, symbol: String? = nil,
        mark: Mark = .off, action: @escaping () -> Void,
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.symbol = symbol
        self.mark = mark
        self.action = action
    }
}

/// A button that opens a list of choices above itself: for a bar near the bottom edge of a
/// window, where a menu would open downward and leave the window.
///
/// A click on a choice takes it, and closes the list unless the list is one to take several
/// choices from; the arrow keys move through the list, Return takes the highlighted choice and
/// Escape closes. Over the list there can be something of the caller's: a field to add a choice.
public struct ChoiceListButton<Header: View>: View {
    private let title: Text
    private let symbol: String?
    private let choices: [Choice]
    private let empty: Text
    private let staysOpen: Bool
    private let header: Header

    @State private var isOpen = false
    @State private var highlightedID: Choice.ID?

    /// - Parameters:
    ///   - symbol: shown alone, with the title as its accessible name, where there is no room
    ///     for the title.
    ///   - empty: what the list says when there is nothing to choose.
    ///   - staysOpen: keep the list open after a choice, to take several.
    ///   - header: shown over the list.
    public init(
        _ title: Text, symbol: String? = nil, choices: [Choice], empty: Text, staysOpen: Bool = false,
        @ViewBuilder header: () -> Header,
    ) {
        self.title = title
        self.symbol = symbol
        self.choices = choices
        self.empty = empty
        self.staysOpen = staysOpen
        self.header = header()
    }

    public var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            if let symbol {
                Label { title } icon: { Image(systemName: symbol) }
                    .labelStyle(.iconOnly)
            } else {
                HStack(spacing: Spacing.xs) {
                    title
                    Image(systemName: "chevron.up")
                        .font(Typography.badge)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            VStack(spacing: 0) {
                header
                list
            }
            .frame(width: Self.width)
        }
    }

    @ViewBuilder private var list: some View {
        if choices.isEmpty {
            empty
                .foregroundStyle(.secondary)
                .padding(Spacing.l)
                .frame(maxWidth: .infinity)
        } else {
            List(selection: $highlightedID) {
                ForEach(choices) { choice in
                    row(for: choice)
                }
            }
            .scrollContentBackground(.hidden)
            .onKeyPress(.return) {
                guard let choice = choices.first(where: { $0.id == highlightedID }) else { return .ignored }
                take(choice)
                return .handled
            }
            .frame(height: min(listHeight, Self.maximumHeight))
        }
    }

    private func row(for choice: Choice) -> some View {
        HStack(spacing: Spacing.s) {
            Group {
                switch choice.mark {
                case .off: Color.clear
                case .all: Image(systemName: "checkmark")
                case .part: Image(systemName: "minus")
                }
            }
            .font(Typography.badge)
            .frame(width: Spacing.m)
            .accessibilityHidden(true)
            if let color = choice.color {
                Circle()
                    .fill(color)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .accessibilityHidden(true)
            } else if let symbol = choice.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: choice.title)
                    .lineLimit(1)
                if let subtitle = choice.subtitle {
                    Text(verbatim: subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        // A click takes the choice; the arrow keys only move the highlight.
        .onTapGesture { take(choice) }
        .tag(choice.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(choice.mark == .all ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { take(choice) }
    }

    private func take(_ choice: Choice) {
        if !staysOpen {
            isOpen = false
        }
        choice.action()
    }

    private static var width: CGFloat {
        260
    }

    /// The height the list needs to show every choice: a row with a line of context under its
    /// title is taller.
    private var listHeight: CGFloat {
        choices.reduce(Spacing.xl) { $0 + ($1.subtitle == nil ? Self.rowHeight : Self.tallRowHeight) }
    }

    private static var rowHeight: CGFloat {
        24
    }

    private static var tallRowHeight: CGFloat {
        40
    }

    private static var maximumHeight: CGFloat {
        320
    }

    private static var dotSize: CGFloat {
        10
    }
}

public extension ChoiceListButton where Header == EmptyView {
    /// A list with nothing over it.
    init(_ title: Text, symbol: String? = nil, choices: [Choice], empty: Text, staysOpen: Bool = false) {
        self.init(title, symbol: symbol, choices: choices, empty: empty, staysOpen: staysOpen) { EmptyView() }
    }
}

#Preview("Choice list buttons") {
    HStack(spacing: Spacing.l) {
        ChoiceListButton(
            Text("Tag"),
            choices: [
                Choice(id: "red", title: "Red", color: .red, mark: .all) {},
                Choice(id: "green", title: "Green", color: .green, mark: .part) {},
                Choice(id: "print", title: "To print") {},
            ],
            empty: Text("No Tags"),
        )
        ChoiceListButton(
            Text("Move to…"), symbol: "folder",
            choices: [Choice(id: "a", title: "A folder with a name long enough to be cut", subtitle: "Inside another", symbol: "folder") {}],
            empty: Text("No Other Folder"),
        )
        ChoiceListButton(Text("Recipe"), choices: [], empty: Text("No Recipes"))
            .disabled(true)
    }
    .padding(Spacing.xl)
}
