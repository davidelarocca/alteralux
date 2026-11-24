import DesignSystem
import SwiftUI

/// The strip of open photos under the viewer.
struct FilmstripView: View {
    @Environment(AppModel.self) private var model
    @ReduceMotion private var reduceMotion

    /// Width of the "add photos" button, in points (its height follows the thumbnails).
    private static let addButtonWidth: CGFloat = 44

    var body: some View {
        thumbnails
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ThumbnailCell.size.height + 2 * Spacing.s)
            .background(.bar)
    }

    private var thumbnails: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Spacing.s) {
                    ForEach(model.photos) { item in
                        Button {
                            model.select(item)
                        } label: {
                            ThumbnailCell(image: item.thumbnail, isSelected: item.id == model.selectedID)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .help(item.name)
                        .accessibilityLabel(item.name)
                        .accessibilityAddTraits(item.id == model.selectedID ? .isSelected : [])
                        .contextMenu {
                            Button("Remove from Strip") { model.remove(item) }
                        }
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
