import CoreGraphics
import Foundation
import Testing
@testable import AlteraluxUI

/// The rows of the library's grid: each photo as wide as its shape asks, every row but the last
/// reaching both edges.
struct LibraryRowsTests {
    private func photo(_ name: String) -> URL {
        URL(fileURLWithPath: "/photos/\(name).jpg")
    }

    /// Photos named after their shape: "wide" is 3:2, "tall" 2:3, "square" 1:1.
    private func rows(_ names: [String], width: CGFloat) -> LibraryRows {
        LibraryRows(
            photos: names.map(photo),
            aspectRatio: { url in
                let name = url.deletingPathExtension().lastPathComponent
                if name.hasPrefix("tall") {
                    return 2.0 / 3.0
                }
                if name.hasPrefix("square") {
                    return 1
                }
                if name.hasPrefix("panorama") {
                    return 6
                }
                if name.hasPrefix("sliver") {
                    return 0.1
                }
                return 1.5
            },
            width: width, height: 120, spacing: 10,
        )
    }

    @Test func eachPhotoIsAsWideAsItsShapeAsks() {
        let grid = rows(["wide1", "tall1", "square1"], width: 1000)
        #expect(grid.rows.count == 1)
        #expect(grid.rows[0].items.map(\.width) == [180, 80, 120])
        // Each starts where the one before ends, plus the space between them.
        #expect(grid.rows[0].items.map(\.offset) == [0, 190, 280])
    }

    @Test func aFullRowTakesThePhotosThatKeepItNearestItsHeight() {
        // 180 + 10 + 180 = 370 fits in 400: made taller by 400 / 370 it reaches the edge, nearer
        // 120 than a third photo made shorter would be.
        let grid = rows(["wide1", "wide2", "wide3", "tall1", "wide4"], width: 400)
        #expect(grid.rows.map { $0.items.map(\.photo.lastPathComponent) } == [
            ["wide1.jpg", "wide2.jpg"], ["wide3.jpg", "tall1.jpg", "wide4.jpg"],
        ])
        #expect(grid.rows.map(\.id) == [0, 1])
        #expect(grid.rows[0].items.map(\.width) == [195, 195] && grid.rows[0].items[1].offset == 205)
        // The second row would be half again as tall with two photos: it takes a third, shorter.
        #expect(grid.rows.map(\.height) == [130, 104])
    }

    @Test func everyFullRowReachesBothEdges() {
        let names = ["wide1", "tall1", "square1", "wide2", "tall2", "wide3", "square2", "wide4", "tall3"]
        for width in [400.0, 523, 777, 1000] {
            let grid = rows(names, width: width)
            for row in grid.rows.dropLast() {
                let last = row.items[row.items.count - 1]
                #expect(row.items[0].offset == 0 && last.offset + last.width == width)
            }
            // The last row keeps the height asked for.
            #expect(grid.rows.last?.height == 120)
        }
    }

    @Test func aRowIsNeverStretchedMoreThanHalfAgain() {
        // An upright photo alone in a 150 pt grid would have to be nearly twice as tall: it
        // stops at half again, and the row keeps a gap.
        let grid = rows(["tall1", "wide1"], width: 150)
        #expect(grid.rows[0].height == 180 && grid.rows[0].items.map(\.width) == [120])
    }

    @Test func extremeShapesStayWithinReason() {
        let grid = rows(["panorama1", "sliver1"], width: 1000)
        // Two and a half times the height at most, half of it at least.
        #expect(grid.rows[0].items.map(\.width) == [300, 60])
        // In a grid narrower than a photo, the photo is as wide as the grid.
        #expect(rows(["wide1", "wide2"], width: 150).rows.map { $0.items.map(\.width) } == [[150], [150]])
    }

    @Test func noPhotosGiveNoRows() {
        #expect(rows([], width: 400).rows.isEmpty)
    }

    @Test func upAndDownGoToThePhotoNearestAboveOrBelow() {
        // Row 0: wide1 (0...195), wide2 (205...400). Row 1: tall1 (0...89), tall2 (99...188),
        // wide3 (198...400). Row 2: wide4.
        let grid = rows(["wide1", "wide2", "tall1", "tall2", "wide3", "wide4"], width: 400)
        #expect(grid.rows.map(\.items.count) == [2, 3, 1])
        #expect(grid.photo(from: photo("wide1"), rowsDown: 1) == photo("tall2"))
        #expect(grid.photo(from: photo("wide2"), rowsDown: 1) == photo("wide3"))
        #expect(grid.photo(from: photo("tall1"), rowsDown: -1) == photo("wide1"))
        #expect(grid.photo(from: photo("wide3"), rowsDown: 1) == photo("wide4"))
        // Nothing above the first row, below the last, or for a photo that is not there.
        #expect(grid.photo(from: photo("wide1"), rowsDown: -1) == nil)
        #expect(grid.photo(from: photo("wide4"), rowsDown: 1) == nil)
        #expect(grid.photo(from: photo("missing"), rowsDown: 1) == nil)
    }
}
