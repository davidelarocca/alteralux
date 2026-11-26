import AlteraluxKit
import DesignSystem
import SwiftUI

/// The strip of open photos under the viewer.
struct FilmstripView: View {
    @Environment(AppModel.self) private var model
    @ReduceMotion private var reduceMotion
    /// What a photo's menu asks before it acts: a new tag's name, whether to trash the photo.
    @State private var question: PhotoQuestion?

    /// Width of the "add photos" button, in points (its height follows the thumbnails).
    private static let addButtonWidth: CGFloat = 44

    var body: some View {
        thumbnails
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ThumbnailCell.size.height + 2 * Spacing.s)
            .background(.bar)
            .modifier(PhotoQuestionAlerts(question: $question))
    }

    private var thumbnails: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Spacing.s) {
                    ForEach(model.photos) { item in
                        StripThumbnail(item: item) { question = $0 }
                            .id(item.id)
                    }

                    Button {
                        model.isImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: Self.addButtonWidth, height: ThumbnailCell.size.height)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add photos")
                    .accessibilityLabel("Add photos")
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
            }
            .scrollIndicators(.hidden)
            // The thumbnails end where the strip does: drawn past it, they would run on under
            // the adjustments, whose glass shows them.
            .clipped()
            .onChange(of: model.selectedID) { _, selected in
                guard let selected else { return }
                // Scrolling moves content: no animation under Reduce Motion.
                withAnimation(Motion.moving(Motion.standard, reduced: reduceMotion)) {
                    proxy.scrollTo(selected)
                }
            }
        }
    }
}

/// One photo of the strip: its thumbnail, with the library's marks in its corners (adjusted,
/// discarded) and its colored Finder tags as dots. A click shows the photo; its menu acts on it
/// without showing it.
private struct StripThumbnail: View {
    @Environment(AppModel.self) private var model
    let item: PhotoItem
    /// Asks before one of the menu's actions.
    let ask: (PhotoQuestion) -> Void
    /// What the menu's Share… shares, until the picker opens over the thumbnail.
    @State private var sharing: [URL]?

    var body: some View {
        let tags = model.tags(of: item)
        let isDiscarded = model.isDiscarded(item)
        Button {
            model.select(item)
        } label: {
            ThumbnailCell(image: item.thumbnail, isSelected: model.isOnScreen(item))
                .overlay(alignment: .topLeading) { TagMark(tags) }
                .overlay(alignment: .bottomTrailing) {
                    if item.hasAdjustments {
                        PhotoMark.adjusted
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isDiscarded {
                        PhotoMark.discarded
                    }
                }
        }
        .buttonStyle(.plain)
        .help(item.name)
        .accessibilityLabel(label(isDiscarded: isDiscarded))
        .accessibilityValue(Text(verbatim: tags.map(\.name).joined(separator: ", ")))
        .accessibilityAddTraits(model.isOnScreen(item) ? .isSelected : [])
        .contextMenu { StripPhotoMenu(item: item, ask: ask) { sharing = $0 } }
        .sharePicker(items: $sharing)
    }

    /// The photo's name, and what its marks say, as the library's grid says it.
    private func label(isDiscarded: Bool) -> Text {
        if isDiscarded {
            return Text("\(item.name), discarded")
        }
        return item.hasAdjustments ? Text("\(item.name), with adjustments") : Text(verbatim: item.name)
    }
}
