import SwiftUI

/// The strip of open photos under the viewer.
struct FilmstripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(model.photos) { item in
                        Button {
                            model.select(item)
                        } label: {
                            FilmstripCell(item: item, isSelected: item.id == model.selectedID)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .contextMenu {
                            Button("Remove from Strip") { model.remove(item) }
                        }
                    }

                    Button {
                        model.isImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: FilmstripCell.size.height)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add photos")
                    .accessibilityLabel("Add photos")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
        }
        .frame(height: FilmstripCell.size.height + 16)
        .background(.bar)
    }
}

private struct FilmstripCell: View {
    let item: PhotoItem
    let isSelected: Bool

    static let size = CGSize(width: 84, height: 56)

    var body: some View {
        ZStack {
            Color(white: 0.2)
            if let thumbnail = item.thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(.rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1)
        }
        .help(item.name)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
