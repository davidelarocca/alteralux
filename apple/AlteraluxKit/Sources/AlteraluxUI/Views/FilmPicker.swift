import DesignSystem
import SwiftUI

/// The list to choose the film from, opened from the heading of the inspector: the system's
/// search field over the system's list of the films, grouped by kind, each with its emblem,
/// without lines between them. It grows with the window.
///
/// The search field keeps the keyboard: typing narrows the list, the arrow keys move through
/// it, Return chooses the highlighted film and Escape closes the list.
struct FilmPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The height of the pane the list opens from, when known: the list grows with it.
    let paneHeight: CGFloat?

    @State private var query = ""
    /// The row the arrow keys have reached: the list's selection.
    @State private var highlightedID: String?

    /// The size of the list at the window's smallest, in points: it opens inside the window.
    static let size = CGSize(width: 300, height: 420)
    /// The tallest the list grows in a tall window, in points.
    static let maximumHeight: CGFloat = 640
    /// The part of the pane above the list and under it: the heading it opens from, its arrow
    /// and a margin to the window's bottom edge.
    static let paneReserve: CGFloat = 130

    init(paneHeight: CGFloat? = nil) {
        self.paneHeight = paneHeight
    }

    /// As tall as the pane leaves room for, between the smallest and the tallest size.
    static func height(paneHeight: CGFloat?) -> CGFloat {
        guard let paneHeight else { return size.height }
        return min(max(paneHeight - paneReserve, size.height), maximumHeight)
    }

    private var groups: [FilmGroup] {
        model.filmCatalogue.groups(matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                String(localized: "Search films"), prompt: String(localized: "Search"), text: $query,
                onMove: moveHighlight(by:), onSubmit: { choose(highlightedID) },
            )
            .padding(Spacing.m)
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                FilmList(groups: groups, selectedID: model.settings.filmID, highlightedID: $highlightedID) {
                    choose($0)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.height(paneHeight: paneHeight))
        .onAppear { highlightedID = model.settings.filmID }
        .onChange(of: query) {
            // Keep a row highlighted for Return: the first match when the old one is filtered out.
            let listed = groups.flatMap(\.films).map(\.id)
            if highlightedID.map(listed.contains) != true {
                highlightedID = listed.first
            }
        }
    }

    private func moveHighlight(by offset: Int) {
        highlightedID = FilmCatalogue.film(from: highlightedID, offset: offset, in: groups)
    }

    private func choose(_ id: String?) {
        guard let id else { return }
        model.chooseFilm(id)
        dismiss()
    }
}

/// The films under the search field: a list with a section for each kind.
private struct FilmList: View {
    let groups: [FilmGroup]
    let selectedID: String
    @Binding var highlightedID: String?
    let choose: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $highlightedID) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.films) { film in
                            row(for: film)
                        }
                    } header: {
                        title(of: group.kind)
                    }
                }
            }
            // Thin scroll bars, as the photo's: wide ones would stay with a mouse.
            .thinScrollBars()
            .scrollContentBackground(.hidden)
            // With the keyboard in the list itself, Return chooses as it does from the field.
            .onKeyPress(.return) {
                guard let highlightedID else { return .ignored }
                choose(highlightedID)
                return .handled
            }
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
            .onChange(of: highlightedID) { _, highlighted in
                if let highlighted {
                    proxy.scrollTo(highlighted)
                }
            }
        }
    }

    private func row(for film: FilmEntry) -> some View {
        HStack(spacing: Spacing.m) {
            FilmEmblem(ground: film.look.ground, band: film.look.band, label: film.look.label)
            Text(verbatim: film.name)
                .lineLimit(1)
            Spacer(minLength: 0)
            if film.id == selectedID {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Spacing.xxs)
        // The section titles divide the list; lines between the films would crowd the emblems.
        .listRowSeparator(.hidden)
        .contentShape(.rect)
        // A click chooses; the arrow keys only move the selection.
        .onTapGesture { choose(film.id) }
        .tag(film.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(film.id == selectedID ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { choose(film.id) }
    }

    private func title(of kind: FilmKind) -> Text {
        switch kind {
        case .colorNegative: Text("Color Negatives")
        case .slide: Text("Slides")
        case .blackAndWhite: Text("Black and White")
        case .motionPicture: Text("Motion Picture")
        }
    }
}
