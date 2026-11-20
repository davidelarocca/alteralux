import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// The camera RAW kept for the tests of this target.
private let rawFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AlteraluxUITests
    .deletingLastPathComponent() // Tests
    .appendingPathComponent("Fixtures/gray-card.dng")

/// Sorting the photos of a folder, and showing them by kind and by Finder tag.
@MainActor
struct LibrarySortTests {
    /// A folder with three pictures, wide ones, and a RAW, with dates and tags of their own.
    private struct Fixture {
        let folder: URL
        let first, second, third, raw: URL

        @MainActor
        init() throws {
            let pictures = try WindowedTests.writeTestPictures(count: 3)
            folder = pictures[0].deletingLastPathComponent()
            (first, second, third) = (pictures[0], pictures[1], pictures[2])
            raw = folder.appendingPathComponent("Raw.dng")
            try FileManager.default.copyItem(at: rawFixture, to: raw)
            // The second is the oldest, then the RAW, the third, and the first is the newest.
            for (photo, age) in [(second, 4.0), (raw, 3.0), (third, 2.0), (first, 1.0)] {
                let date = Date(timeIntervalSinceReferenceDate: 700_000_000 - age * 86400)
                try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: photo.path)
            }
            try Self.tag(first, ["Trip\n2"])
            try Self.tag(third, ["Trip\n2", "Print\n6"])
            try Self.tag(raw, ["Plain"])
        }

        /// Writes Finder tags as the Finder keeps them: a name, and the number of its color.
        static func tag(_ file: URL, _ tags: [String]) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
            let status = data.withUnsafeBytes {
                setxattr(file.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, data.count, 0, 0)
            }
            try #require(status == 0)
        }

        @MainActor
        func library() async throws -> LibraryModel {
            let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: folder.appendingPathComponent("support"))
            try await model.library.add(folder)
            return model.library
        }

        func remove() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func names(_ photos: [URL]) -> [String] {
        photos.map(\.lastPathComponent)
    }

    /// A photo under the address the library gives it, which is the one it answers to: the
    /// same file can come with two addresses, through a link in its path.
    private func photo(_ name: String, in library: LibraryModel) throws -> URL {
        try #require(library.photos.first { $0.lastPathComponent == name })
    }

    @Test func thePhotosAreSortedByNameDateOrKind() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let library = try await fixture.library()

        #expect(names(library.visiblePhotos) == ["Picture 1.png", "Picture 2.png", "Picture 3.png", "Raw.dng"])
        library.sortsAscending = false
        #expect(names(library.visiblePhotos) == ["Raw.dng", "Picture 3.png", "Picture 2.png", "Picture 1.png"])

        library.sort = .date
        #expect(names(library.visiblePhotos) == ["Picture 1.png", "Picture 3.png", "Raw.dng", "Picture 2.png"])
        library.sortsAscending = true
        #expect(names(library.visiblePhotos) == ["Picture 2.png", "Raw.dng", "Picture 3.png", "Picture 1.png"])

        // By kind, and by name within a kind.
        library.sort = .kind
        #expect(names(library.visiblePhotos) == ["Raw.dng", "Picture 1.png", "Picture 2.png", "Picture 3.png"])

        // The arrow keys follow the order on screen.
        try library.click(photo("Raw.dng", in: library))
        library.moveSelection(by: 1)
        #expect(try library.selection == [photo("Picture 1.png", in: library)])
    }

    @Test func thePhotosAreShownByKindAndByTag() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let library = try await fixture.library()
        #expect(!library.hasFilters && library.filteredCount == 4)

        library.kinds = .raw
        #expect(names(library.visiblePhotos) == ["Raw.dng"] && library.hasFilters)
        library.kinds = .other
        #expect(names(library.visiblePhotos) == ["Picture 1.png", "Picture 2.png", "Picture 3.png"])

        // The tags to choose from are the folder's, each once, with its color when it has one.
        #expect(library.tagsInFolder == [
            FinderTag(name: "Plain"), FinderTag(name: "Print", color: .red), FinderTag(name: "Trip", color: .green),
        ])
        library.tagFilter = "Trip"
        #expect(names(library.visiblePhotos) == ["Picture 1.png", "Picture 3.png"])
        // A photo the filters hide leaves the selection.
        library.clearFilters()
        library.selectAll()
        library.tagFilter = "Print"
        #expect(try library.selection == [photo("Picture 3.png", in: library)])
        #expect(library.filteredCount == 4)

        library.clearFilters()
        #expect(library.visiblePhotos.count == 4 && !library.hasFilters)
    }

    @Test func aTagPutOnPhotosShowsAtOnceAndTheSizesAddUp() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let library = try await fixture.library()

        let sizes = try [fixture.first, fixture.raw].map { photo in
            try Int64(#require(photo.resourceValues(forKeys: [.fileSizeKey]).fileSize))
        }
        let (first, second) = try (photo("Picture 1.png", in: library), photo("Picture 2.png", in: library))
        #expect(try library.size(of: [first, photo("Raw.dng", in: library)]) == sizes[0] + sizes[1])
        #expect(library.size(of: library.visiblePhotos) > sizes[0] + sizes[1])

        library.setTag(FinderTag(name: "Keep", color: .blue), isOn: true, for: [second])
        let deadline = ContinuousClock.now + .seconds(60)
        while library.infos[second]?.tags.contains(FinderTag(name: "Keep", color: .blue)) != true {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for the tag to show.")
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(library.tagsInFolder.map(\.name).contains("Keep"))
        // The shape of each photo is known for the grid: these pictures are twice as wide as tall.
        #expect(library.infos[first]?.aspectRatio == 2)
    }

    /// The tags offered for a selection are the Finder's labels, never its "none", and the
    /// user's own with the color they were made with.
    @Test func aTagOfOnesOwnIsMadeWithItsColor() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = AppModel(dataDirectory: WindowedTests.engineData, editsDirectory: fixture.folder.appendingPathComponent("support"))
        await model.addFolder(fixture.folder)
        let second = try photo("Picture 2.png", in: model.library)
        model.library.click(second)

        // The Finder's seven labels come first, each with its color, and "none" is not one.
        #expect(model.tagChoices.prefix(7).map(\.color) == FinderTagColor.allCases.map(Optional.some))
        model.addTag(named: "  ", color: .red)
        model.addTag(named: " Event ", color: .purple)
        #expect(PhotoInfoReader.tags(of: second) == [FinderTag(name: "Event", color: .purple)])
        let deadline = ContinuousClock.now + .seconds(60)
        while model.tagChoices.last != TagChoice(name: "Event", color: .purple, carriedBy: 1) {
            try #require(ContinuousClock.now < deadline, "Waited 60 seconds for the tag to show with its color.")
            try await Task.sleep(for: .milliseconds(5))
        }
        // Chosen again, it comes off.
        model.toggleTag("Event", color: .purple)
        #expect(PhotoInfoReader.tags(of: second).isEmpty)
        #expect(model.alertMessage == nil)
    }
}
