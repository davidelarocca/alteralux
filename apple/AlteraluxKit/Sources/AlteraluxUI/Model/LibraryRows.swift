import CoreGraphics
import Foundation

/// The photos of the library's grid laid out in rows, each photo as wide as its own shape asks:
/// an upright photo is narrow, a panorama is wide, and none sits in a tile made for another
/// shape. Every row but the last reaches both edges of the grid, as in Photos: it takes the
/// photos that keep it nearest the height asked for, and is made that little taller or shorter.
struct LibraryRows: Equatable {
    /// One photo in its row.
    struct Item: Equatable, Identifiable {
        let photo: URL
        /// The width it is drawn at, in points.
        let width: CGFloat
        /// Where it starts in its row, in points from the leading edge.
        let offset: CGFloat

        var id: URL {
            photo
        }
    }

    struct Row: Equatable, Identifiable {
        /// The position of the row, from 0.
        let id: Int
        let items: [Item]
        /// The height its photos are drawn at, in points.
        let height: CGFloat
    }

    let rows: [Row]

    /// The narrowest and the widest a photo is drawn, as a share of the rows' height: a shape
    /// more extreme than these is cropped by its thumbnail rather than given a sliver or a
    /// whole row.
    static let widthRange: ClosedRange<CGFloat> = 0.5 ... 2.5

    /// How much taller than the height asked for a row is made to reach the grid's edges, at
    /// most; and as much shorter, the other way. A row that would need more keeps a gap.
    static let maximumStretch: CGFloat = 1.5

    /// - Parameters:
    ///   - photos: the photos, in the order they are shown.
    ///   - aspectRatio: the width over the height of a photo.
    ///   - width: the room a row has, in points.
    ///   - height: the height of every row, in points.
    ///   - spacing: the space between two photos of a row, in points.
    init(photos: [URL], aspectRatio: (URL) -> Double, width: CGFloat, height: CGFloat, spacing: CGFloat) {
        var rows: [Row] = []
        // The photos of the row being filled, with their widths at the height asked for.
        var pending: [(photo: URL, width: CGFloat)] = []
        // How much a row of these photos is stretched to fill the grid's width.
        func stretch(_ items: [(photo: URL, width: CGFloat)]) -> CGFloat {
            let room = width - spacing * CGFloat(items.count - 1)
            return room / items.reduce(0) { $0 + $1.width }
        }
        func closeRow(stretchedBy factor: CGFloat) {
            rows.append(Self.row(rows.count, pending, factor: factor, height: height, spacing: spacing))
            pending = []
        }
        for photo in photos {
            let ratio = min(max(CGFloat(aspectRatio(photo)), Self.widthRange.lowerBound), Self.widthRange.upperBound)
            // A photo wider than the grid still has its row to itself.
            let itemWidth = min((height * ratio).rounded(), max(width, height * Self.widthRange.lowerBound))
            let longer = pending + [(photo, itemWidth)]
            let used = longer.reduce(0) { $0 + $1.width } + spacing * CGFloat(longer.count - 1)
            guard !pending.isEmpty, used > width else {
                pending = longer
                continue
            }
            // The row is full: it ends here, made taller, or takes this photo too, made shorter,
            // whichever leaves it nearer the height asked for.
            let taller = stretch(pending)
            let shorter = stretch(longer)
            if shorter >= 1 / Self.maximumStretch, abs(log(shorter)) < abs(log(taller)) {
                pending = longer
                closeRow(stretchedBy: shorter)
            } else {
                closeRow(stretchedBy: min(taller, Self.maximumStretch))
                pending = [(photo, itemWidth)]
            }
        }
        if !pending.isEmpty {
            // The last row keeps the height asked for, unless its photos pass the grid's width.
            closeRow(stretchedBy: min(stretch(pending), 1))
        }
        self.rows = rows
    }

    /// A row of photos made `factor` times as tall as `height`, each as wide in proportion. The
    /// last photo takes what rounding leaves, so a row that fills the grid ends at its edge.
    private static func row(
        _ id: Int, _ photos: [(photo: URL, width: CGFloat)], factor: CGFloat, height: CGFloat, spacing: CGFloat,
    ) -> Row {
        let total = (photos.reduce(0) { $0 + $1.width } * factor).rounded()
        var items: [Item] = []
        var offset: CGFloat = 0
        var drawn: CGFloat = 0
        for (index, entry) in photos.enumerated() {
            let itemWidth = index == photos.count - 1 ? total - drawn : (entry.width * factor).rounded(.down)
            items.append(Item(photo: entry.photo, width: itemWidth, offset: offset))
            offset += itemWidth + spacing
            drawn += itemWidth
        }
        return Row(id: id, items: items, height: (height * factor).rounded())
    }

    /// The photo right above or below `photo`: the one of the next row in that direction whose
    /// middle is nearest to this photo's. `nil` on the first or the last row, or for a photo
    /// that is not in the grid.
    func photo(from photo: URL, rowsDown: Int) -> URL? {
        guard
            let row = rows.first(where: { $0.items.contains { $0.photo == photo } }),
            let item = row.items.first(where: { $0.photo == photo }),
            rows.indices.contains(row.id + rowsDown)
        else { return nil }
        let middle = item.offset + item.width / 2
        return rows[row.id + rowsDown].items.min { lhs, rhs in
            abs(lhs.offset + lhs.width / 2 - middle) < abs(rhs.offset + rhs.width / 2 - middle)
        }?.photo
    }
}
