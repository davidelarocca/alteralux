import DesignSystem
import SwiftUI

/// The list to choose the film from, opened from the heading of the inspector: a search field
/// over the system's list of the films, grouped by kind, each with its emblem.
///
/// The search field keeps the keyboard: typing narrows the list, the arrow keys move through
/// it, Return chooses the highlighted film and Escape closes the list.
struct FilmPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    /// The row the arrow keys have reached: the list's selection.
    @State private var highlightedID: String?
    @FocusState private var searchIsFocused: Bool

    /// The size of the list, in points: it opens inside the window at its smallest.
    static let size = CGSize(width: 300, height: 420)

    private var groups: [FilmGroup] {
        model.filmCatalogue.groups(matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search films", text: $query, prompt: Text("Search"))
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onSubmit { choose(highlightedID) }
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
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear {
            highlightedID = model.settings.filmID
            searchIsFocused = true
        }
        .onChange(of: query) {
            // Keep a row highlighted for Return: the first match when the old one is filtered out.
            let listed = groups.flatMap(\.films).map(\.id)
            if highlightedID.map(listed.contains) != true {
                highlightedID = listed.first
            }
        }
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        highlightedID = FilmCatalogue.film(from: highlightedID, offset: offset, in: groups)
        return .handled
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
