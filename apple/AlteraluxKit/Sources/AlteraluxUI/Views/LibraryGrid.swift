import DesignSystem
import SwiftUI

/// The photos of the folder on screen, in a grid, with the count and the size of the thumbnails
/// under it.
struct LibraryGrid: View {
    @Environment(AppModel.self) private var model
    @Binding var isAddingFolder: Bool
    @AppStorage("library.thumbnailSize") private var thumbnailSize = LibraryGrid.thumbnailSizes.lowerBound + 40
    @State private var isEmptyingDiscarded = false

    /// The widths a thumbnail can have, in points.
    static let thumbnailSizes = 120.0 ... 320.0
    private static let thumbnailSizeStep = 20.0
    /// A thumbnail is this much less tall than wide: room for an upright photo and a wide one.
    private static let tileProportion = 0.75
    /// Width of the slider for the size of the thumbnails, in points.
    private static let sliderWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.DS.viewerSurround)
            if !model.library.selection.isEmpty {
                Divider()
                LibrarySelectionBar()
            }
            Divider()
            statusBar
        }
        .confirmationDialog(
            "Move the discarded photos of this folder to the Trash?", isPresented: $isEmptyingDiscarded,
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.emptyDiscarded() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        let library = model.library
        if library.isEmpty {
            ContentUnavailableView {
                Label("Add a Folder", systemImage: "folder.badge.plus")
            } description: {
                Text("The library shows the photos of the folders you add, as they are on disk.")
            } actions: {
                Button("Add Folder…") { isAddingFolder = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if library.visiblePhotos.isEmpty {
            ContentUnavailableView {
                Label("No Photos", systemImage: "photo.on.rectangle")
            } description: {
                if library.selectedFolder == nil {
                    Text("Choose a folder.")
                } else if library.filter == .adjusted {
                    Text("No photo in this folder has adjustments yet.")
                } else if library.filter == .discarded {
                    Text("No photo in this folder is discarded.")
                } else {
                    Text("This folder has no photos.")
                }
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        let library = model.library
        let size = CGSize(width: thumbnailSize, height: thumbnailSize * Self.tileProportion)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: Spacing.m)], spacing: Spacing.m) {
                ForEach(library.visiblePhotos, id: \.self) { photo in
                    LibraryTile(
                        photo: photo, size: size,
                        isSelected: library.selection.contains(photo),
                        hasAdjustments: library.adjusted.contains(photo),
                    )
                }
            }
            .padding(Spacing.m)
        }
        // The grid takes the keys: arrows move through the photos, Return develops.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            library.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            library.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard let photo = library.focusedPhoto else { return .ignored }
            model.develop(photo)
            return .handled
        }
        .onKeyPress(.escape) {
            library.clearSelection()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{7F}")]) { _ in
            guard !library.selection.isEmpty else { return .ignored }
            model.discardSelection()
            return .handled
        }
        .onKeyPress(keys: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            library.selectAll()
            return .handled
        }
    }

    private var statusBar: some View {
        let library = model.library
        return HStack(spacing: Spacing.s) {
            Group {
                if library.selection.isEmpty {
                    Text("\(Text("\(library.visiblePhotos.count) photos")) · \(Text("double-click to develop"))")
                } else {
                    Text("\(Text("\(library.visiblePhotos.count) photos")) · \(Text("\(library.selection.count) selected"))")
                }
            }
            .font(Typography.technical)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: Spacing.s)
            if library.filter == .discarded, !library.visiblePhotos.isEmpty {
                Button("Empty Discarded…") { isEmptyingDiscarded = true }
                    .help("Move the discarded photos of this folder to the Trash")
            }
            ParameterSlider(
                "Thumbnail size", value: $thumbnailSize, in: Self.thumbnailSizes,
                step: Self.thumbnailSizeStep, defaultValue: Self.thumbnailSizes.lowerBound + 40,
            )
            .labelsHidden()
            .frame(width: Self.sliderWidth)
            .help("Size of the thumbnails")
        }
        .controlSize(.small)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
    }
}

/// One photo of the grid: its thumbnail, its name, and a mark when it has adjustments.
private struct LibraryTile: View {
    @Environment(AppModel.self) private var model
    let photo: URL
    let size: CGSize
    let isSelected: Bool
    let hasAdjustments: Bool
    @State private var image: CGImage?

    /// Thumbnails are asked for in two sizes, in pixels, so the ones kept can be used again
    /// whatever the slider says: enough for the smaller tiles, and for the larger ones.
    private var pixels: Int {
        size.width <= 160 ? 320 : 640
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ThumbnailCell(image: image, isSelected: isSelected, size: size, showsWholePhoto: true)
                .overlay(alignment: .bottomTrailing) {
                    if hasAdjustments {
                        Image(systemName: "slider.horizontal.3")
                            .font(Typography.badge)
                            .padding(Spacing.xs)
                            .background(.regularMaterial, in: .rect(cornerRadius: Radius.control))
                            .padding(Spacing.xs)
                            .accessibilityHidden(true)
                    }
                }
            Text(photo.lastPathComponent)
                .font(Typography.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size.width)
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) { model.develop(photo) }
        .gesture(TapGesture().modifiers(.command).onEnded { model.library.click(photo, toggling: true) })
        .gesture(TapGesture().modifiers(.shift).onEnded { model.library.click(photo, extending: true) })
        .onTapGesture { model.library.click(photo) }
        .help(photo.lastPathComponent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.library.click(photo) }
        .accessibilityAction(named: "Develop") { model.develop(photo) }
        .task(id: pixels) {
            image = await model.library.thumbnails.thumbnail(for: photo, maxDimension: pixels)
        }
    }

    private var label: Text {
        hasAdjustments ? Text("\(photo.lastPathComponent), with adjustments") : Text(verbatim: photo.lastPathComponent)
    }
}
