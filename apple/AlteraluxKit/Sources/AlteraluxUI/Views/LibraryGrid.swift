import AlteraluxKit
import AppKit
import DesignSystem
import QuickLook
import SwiftUI

/// The photos of the folder on screen, in a grid, with the count and the size of the thumbnails
/// under it.
struct LibraryGrid: View {
    @Environment(AppModel.self) private var model
    @Binding var isAddingFolder: Bool
    @AppStorage(LibraryGrid.thumbnailSizeKey) private var thumbnailSize = LibraryGrid.defaultThumbnailSize
    @State private var isEmptyingDiscarded = false
    /// The photo Quick Look shows, while it is open.
    @State private var quickLookItem: URL?
    /// The thumbnail size a pinch started from, while the grid is pinched.
    @State private var pinchBase: Double?
    /// Where each photo of the grid is drawn, in the grid's own space, for the rectangle that
    /// selects by dragging.
    @State private var tileFrames: [URL: CGRect] = [:]
    /// The rectangle being dragged over the grid, while it is.
    @State private var marquee: CGRect?
    /// Where the drag started, in the grid's space, and where the pointer is in the part of the
    /// grid in sight: the grid can scroll under a pointer that does not move.
    @State private var marqueeStart: CGPoint?
    @State private var pointerInSight: CGPoint = .zero
    @State private var selectionBeforeMarquee: Set<URL> = []
    @State private var marqueeToggles = false
    /// Scrolls the grid while the rectangle is held near its top or bottom edge.
    @State private var autoscroll: Task<Void, Never>?
    @State private var scrollPosition = ScrollPosition()
    /// Whether the grid has the keys. A click on it gives them, as does its appearing.
    @FocusState private var hasKeys: Bool
    /// The grid's scrolling, kept where reading it redraws nothing: it changes at every step.
    @State private var scroll = ScrollState()

    /// The widths a thumbnail can have, in points.
    static let thumbnailSizes = 120.0 ... 320.0
    static let thumbnailSizeStep = 20.0
    static let defaultThumbnailSize = thumbnailSizes.lowerBound + 40
    /// Where the size of the thumbnails is kept: the grid's slider and the View menu share it.
    static let thumbnailSizeKey = "library.thumbnailSize"
    /// A thumbnail is this much less tall than wide: room for an upright photo and a wide one.
    private static let tileProportion = 0.75
    /// The name of the grid's scrolling space, where photos and the rectangle are placed.
    private static let space = "library.grid"
    /// How far the pointer moves before a press between the photos becomes a drag, in points.
    private static let dragThreshold: CGFloat = 3
    /// How near the top or bottom edge the rectangle starts the grid scrolling, in points; the
    /// further past it, the faster, up to the most it scrolls at a step.
    private static let autoscrollEdge: CGFloat = 24
    private static let autoscrollMaximumStep: CGFloat = 40
    /// How often the grid scrolls a step while the rectangle is held at an edge: once a frame.
    private static let autoscrollInterval = Duration.milliseconds(16)
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
        } else if library.visiblePhotos.isEmpty, library.hasFilters {
            // The photos are there, hidden by the kind or the tag chosen.
            ContentUnavailableView {
                Label("No Photos Match", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("No photo of this folder is of the kind or carries the tag chosen.")
            } actions: {
                Button("Clear Filters") { library.clearFilters() }
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

    /// The photos in rows that reach both edges, each as wide as its own shape asks.
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
                                    photo: item.photo, size: CGSize(width: item.width, height: row.height),
                                    isSelected: library.selection.contains(item.photo),
                                    hasAdjustments: library.adjusted.contains(item.photo),
                                    isDiscarded: library.discarded.contains(item.photo),
                                    tags: library.infos[item.photo]?.tags ?? [],
                                )
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                                    tileFrames[item.photo] = $0
                                }
                            }
                        }
                    }
                }
                // Each row is a place the grid can be scrolled to, for the arrow keys.
                .scrollTargetLayout()
                .padding(Spacing.m)
                // The room around and under the photos takes clicks and drags too; a click on a
                // photo is the photo's.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                .contentShape(.rect)
                .gesture(SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { tap in
                    if !tileFrames.contains(where: { library.visiblePhotos.contains($0.key) && $0.value.contains(tap.location) }) {
                        library.clearSelection()
                    }
                })
                .gesture(marqueeDrag)
                .overlay(alignment: .topLeading) {
                    if let marquee {
                        SelectionMarquee()
                            .frame(width: marquee.width, height: marquee.height)
                            .offset(x: marquee.minX, y: marquee.minY)
                    }
                }
                .coordinateSpace(.named(Self.space))
            }
            // Thin scroll bars, as the photo's: wide ones would stay with a mouse.
            .thinScrollBars()
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: { scroll.geometry = $1 })
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { scroll.height = $0 }
            // The grid takes the keys: arrows move through the photos, Return develops.
            .focusable()
            .focused($hasKeys)
            .focusEffectDisabled()
            .simultaneousGesture(TapGesture().onEnded { hasKeys = true })
            .onAppear { hasKeys = true }
            .modifier(LibraryGridKeys(
                rows: rows, pageRows: max(1, Int(proxy.size.height / (height + Spacing.xl))),
                reveal: { reveal($0, in: rows) }, quickLook: $quickLookItem,
            ))
            // Pinching the grid makes the thumbnails larger or smaller, as in Photos.
            .gesture(MagnifyGesture().onChanged { pinch in
                let base = pinchBase ?? thumbnailSize
                pinchBase = base
                thumbnailSize = min(max(base * pinch.magnification, Self.thumbnailSizes.lowerBound), Self.thumbnailSizes.upperBound)
            }.onEnded { _ in
                pinchBase = nil
                thumbnailSize = (thumbnailSize / Self.thumbnailSizeStep).rounded() * Self.thumbnailSizeStep
            })
            .quickLookPreview($quickLookItem, in: quickLookItems)
        }
    }

    /// A drag that starts between the photos draws a rectangle and selects the photos it
    /// touches, as the Finder does: with Shift it adds to the selection, with Command it turns
    /// each photo it touches on or off. Held near the top or bottom edge, it scrolls the grid.
    private var marqueeDrag: some Gesture {
        DragGesture(minimumDistance: Self.dragThreshold, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if marqueeStart == nil {
                    let modifiers = NSEvent.modifierFlags
                    marqueeToggles = modifiers.contains(.command)
                    selectionBeforeMarquee = modifiers.contains(.command) || modifiers.contains(.shift) ? model.library.selection : []
                    marqueeStart = drag.startLocation
                    startAutoscroll()
                }
                let inSight = scroll.geometry?.visibleRect.origin ?? .zero
                pointerInSight = CGPoint(x: drag.location.x - inSight.x, y: drag.location.y - inSight.y)
                updateMarquee()
            }
            .onEnded { _ in
                autoscroll?.cancel()
                autoscroll = nil
                marquee = nil
                marqueeStart = nil
                selectionBeforeMarquee = []
            }
    }

    /// Draws the rectangle from where the drag started to the pointer, and selects what it touches.
    private func updateMarquee() {
        guard let start = marqueeStart else { return }
        let inSight = scroll.geometry?.visibleRect.origin ?? .zero
        let pointer = CGPoint(x: pointerInSight.x + inSight.x, y: pointerInSight.y + inSight.y)
        let rectangle = CGRect(
            x: min(start.x, pointer.x), y: min(start.y, pointer.y),
            width: abs(pointer.x - start.x), height: abs(pointer.y - start.y),
        )
        marquee = rectangle
        let library = model.library
        let covered = tileFrames.filter { library.visiblePhotos.contains($0.key) && $0.value.intersects(rectangle) }.keys
        library.select(covered: Set(covered), before: selectionBeforeMarquee, toggling: marqueeToggles)
    }

    /// While the rectangle is drawn, scrolls the grid a step each frame the pointer is held near
    /// or past its top or bottom edge, and stretches the rectangle with it.
    private func startAutoscroll() {
        autoscroll?.cancel()
        autoscroll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.autoscrollInterval)
                guard marqueeStart != nil else { continue }
                // Until the grid has scrolled once the system has not said where it is: it is
                // at its top, as tall as measured, and the photos end where the last one does.
                let geometry = scroll.geometry
                let height = geometry?.visibleRect.height ?? scroll.height
                let past = pointerInSight.y > height - Self.autoscrollEdge
                    ? pointerInSight.y - (height - Self.autoscrollEdge)
                    : min(pointerInSight.y - Self.autoscrollEdge, 0)
                guard past != 0 else { continue }
                let step = max(-Self.autoscrollMaximumStep, min(past / 2, Self.autoscrollMaximumStep))
                let offset = geometry?.contentOffset.y ?? 0
                let top = -(geometry?.contentInsets.top ?? 0)
                let contentHeight = geometry?.contentSize.height ?? (tileFrames.values.map(\.maxY).max() ?? 0) + Spacing.m
                let containerHeight = geometry?.containerSize.height ?? scroll.height
                let bottom = max(top, contentHeight - containerHeight + (geometry?.contentInsets.bottom ?? 0))
                let target = min(max(offset + step, top), bottom)
                guard target != offset else { continue }
                // The offset counts from above the toolbar's inset; a position to scroll to
                // counts from the top of the photos.
                scrollPosition.scrollTo(y: target - top)
                updateMarquee()
            }
        }
    }

    /// What Quick Look goes through with its arrows: the selected photos when there are several,
    /// all those shown otherwise, as in the Finder.
    private var quickLookItems: [URL] {
        let library = model.library
        return library.selection.count > 1 ? library.visiblePhotos.filter(library.selection.contains) : library.visiblePhotos
    }

    /// Scrolls the grid as little as needed to bring the row of a photo the keys reached in sight.
    private func reveal(_ photo: URL?, in rows: LibraryRows) {
        guard let photo, let row = rows.rows.first(where: { $0.items.contains { $0.photo == photo } }) else { return }
        scrollPosition.scrollTo(id: row.id)
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
                if library.visiblePhotos.isEmpty {
                    Text("\(library.visiblePhotos.count) photos")
                } else if library.selection.isEmpty {
                    Text("\(Text("\(library.visiblePhotos.count) photos")) · \(size(of: library.visiblePhotos))")
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
                step: Self.thumbnailSizeStep, defaultValue: Self.defaultThumbnailSize,
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

/// Where the grid is scrolled to. A class, not observed: the rectangle that selects reads it,
/// and the grid need not be drawn again each time it scrolls.
@MainActor
private final class ScrollState {
    var geometry: ScrollGeometry?
    /// The height of the grid on screen, known before it first scrolls.
    var height: CGFloat = 0
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
                HStack(spacing: Spacing.xxs) {
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
        .contextMenu { LibraryPhotoMenu(photo: photo) }
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
