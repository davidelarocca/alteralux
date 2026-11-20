import AlteraluxKit
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
                // The actions on the selection float over the photos, which scroll clear of them.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !model.library.selection.isEmpty {
                        LibrarySelectionBar()
                            .padding(.horizontal, Spacing.l)
                            .padding(.bottom, Spacing.l)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.quick, value: model.library.selection.isEmpty)
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

    /// The photos in rows of one height, each as wide as its own shape asks.
    private var grid: some View {
        GeometryReader { proxy in
            let library = model.library
            let height = thumbnailSize * Self.tileProportion
            let rows = LibraryRows(
                photos: library.visiblePhotos,
                aspectRatio: { library.infos[$0]?.aspectRatio ?? PhotoInfo.unknownAspectRatio },
                width: proxy.size.width - Spacing.m * 2, height: height, spacing: Spacing.m,
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(rows.rows) { row in
                        HStack(alignment: .top, spacing: Spacing.m) {
                            ForEach(row.items) { item in
                                LibraryTile(
                                    photo: item.photo, size: CGSize(width: item.width, height: height),
                                    isSelected: library.selection.contains(item.photo),
                                    hasAdjustments: library.adjusted.contains(item.photo),
                                    isDiscarded: library.discarded.contains(item.photo),
                                    tags: library.infos[item.photo]?.tags ?? [],
                                )
                            }
                        }
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
            .onKeyPress(.upArrow) { move(in: rows, rowsDown: -1) }
            .onKeyPress(.downArrow) { move(in: rows, rowsDown: 1) }
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
    }

    /// Goes to the photo above or below the one the keys are on, or to the first photo when
    /// none is selected yet.
    private func move(in rows: LibraryRows, rowsDown: Int) -> KeyPress.Result {
        let library = model.library
        if let photo = library.focusedPhoto {
            if let target = rows.photo(from: photo, rowsDown: rowsDown) {
                library.click(target)
            }
        } else {
            library.moveSelection(by: rowsDown)
        }
        return .handled
    }

    /// The size on disk of some photos, as the Finder writes it.
    private func size(of photos: some Sequence<URL>) -> Text {
        Text(model.library.size(of: photos), format: .byteCount(style: .file))
    }

    private var statusBar: some View {
        let library = model.library
        return HStack(spacing: Spacing.s) {
            // The size is of the photos selected, or of all those shown when none is.
            Group {
                if library.selection.isEmpty {
                    Text("\(Text("\(library.visiblePhotos.count) photos")) · \(size(of: library.visiblePhotos)) · \(Text("double-click to develop"))")
                } else {
                    Text("\(Text("\(library.visiblePhotos.count) photos")) · \(Text("\(library.selection.count) selected")) · \(size(of: library.selection))")
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

/// One photo of the grid, drawn with its own shape: its thumbnail, a mark when it has
/// adjustments or was discarded, and under it its name, after a dot for each colored Finder tag.
private struct LibraryTile: View {
    @Environment(AppModel.self) private var model
    let photo: URL
    let size: CGSize
    let isSelected: Bool
    let hasAdjustments: Bool
    let isDiscarded: Bool
    let tags: [FinderTag]
    @State private var image: CGImage?

    /// The diameter of a tag's dot, in points.
    private static let dotSize: CGFloat = 8

    /// Thumbnails are asked for in two sizes, in pixels, so the ones kept can be used again
    /// whatever the slider says: enough for the smaller tiles, and for the larger ones.
    private var pixels: Int {
        max(size.width, size.height) <= 160 ? 320 : 640
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ThumbnailCell(image: image, isSelected: isSelected, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if hasAdjustments {
                        mark("slider.horizontal.3")
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isDiscarded {
                        mark("xmark")
                    }
                }
            HStack(spacing: Spacing.xs) {
                HStack(spacing: -Spacing.xxs) {
                    ForEach(tags.compactMap(\.color), id: \.self) { color in
                        Circle()
                            .fill(color.swatch)
                            .frame(width: Self.dotSize, height: Self.dotSize)
                    }
                }
                .accessibilityHidden(true)
                Text(photo.lastPathComponent)
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
        .accessibilityValue(Text(verbatim: tags.map(\.name).joined(separator: ", ")))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.library.click(photo) }
        .accessibilityAction(named: "Develop") { model.develop(photo) }
        .task(id: pixels) {
            image = await model.library.thumbnails.thumbnail(for: photo, maxDimension: pixels)
        }
    }

    /// A small mark in a corner of the thumbnail.
    private func mark(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(Typography.badge)
            .padding(Spacing.xs)
            .background(.regularMaterial, in: .rect(cornerRadius: Radius.control))
            .padding(Spacing.xs)
            .accessibilityHidden(true)
    }

    private var label: Text {
        if isDiscarded {
            return Text("\(photo.lastPathComponent), discarded")
        }
        return hasAdjustments ? Text("\(photo.lastPathComponent), with adjustments") : Text(verbatim: photo.lastPathComponent)
    }
}

private extension FinderTagColor {
    /// The color the Finder draws this tag with: the system's own.
    var swatch: Color {
        switch self {
        case .gray: .gray
        case .green: .green
        case .purple: .purple
        case .blue: .blue
        case .yellow: .yellow
        case .red: .red
        case .orange: .orange
        }
    }
}
