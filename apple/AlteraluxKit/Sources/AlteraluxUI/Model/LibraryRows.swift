import CoreGraphics
import Foundation

/// The photos of the library's grid laid out in rows of one height, each photo as wide as its
/// own shape asks: an upright photo is narrow, a panorama is wide, and none sits in a tile
/// made for another shape.
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
    }

    let rows: [Row]

    /// The narrowest and the widest a photo is drawn, as a share of the rows' height: a shape
    /// more extreme than these is cropped by its thumbnail rather than given a sliver or a
    /// whole row.
    static let widthRange: ClosedRange<CGFloat> = 0.5 ... 2.5

    /// - Parameters:
    ///   - photos: the photos, in the order they are shown.
    ///   - aspectRatio: the width over the height of a photo.
    ///   - width: the room a row has, in points.
    ///   - height: the height of every row, in points.
    ///   - spacing: the space between two photos of a row, in points.
    init(photos: [URL], aspectRatio: (URL) -> Double, width: CGFloat, height: CGFloat, spacing: CGFloat) {
        var rows: [Row] = []
        var items: [Item] = []
        var used: CGFloat = 0
        for photo in photos {
            let ratio = min(max(CGFloat(aspectRatio(photo)), Self.widthRange.lowerBound), Self.widthRange.upperBound)
            // A photo wider than the grid still has its row to itself.
            let itemWidth = min((height * ratio).rounded(), max(width, height * Self.widthRange.lowerBound))
            if !items.isEmpty, used + spacing + itemWidth > width {
                rows.append(Row(id: rows.count, items: items))
                items = []
                used = 0
            }
            let offset = items.isEmpty ? 0 : used + spacing
            items.append(Item(photo: photo, width: itemWidth, offset: offset))
            used = offset + itemWidth
        }
        if !items.isEmpty {
            rows.append(Row(id: rows.count, items: items))
        }
        self.rows = rows
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
