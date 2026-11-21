import Foundation
import Testing
@testable import AlteraluxKit

/// Moving, copying, trashing and tagging photos on disk.
struct PhotoFileActionsTests {
    private static let attribute = "com.example.alteralux-test"

    /// Two folders inside one temporary folder, removed with `remove()`.
    private struct Fixture {
        let root: URL
        let source: URL
        let target: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
            source = root.appendingPathComponent("source")
            target = root.appendingPathComponent("target")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }

        @discardableResult
        func file(_ name: String, in folder: URL? = nil, contents: String = "pixels") throws -> URL {
            let url = (folder ?? source).appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            return url
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func setAttribute(_ value: String, on url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path in
            Array(value.utf8).withUnsafeBytes { setxattr(path, Self.attribute, $0.baseAddress, $0.count, 0, 0) }
        }
    }

    private func attribute(on url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path -> String? in
            let size = getxattr(path, Self.attribute, nil, 0, 0, 0)
            guard size >= 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            let read = getxattr(path, Self.attribute, &buffer, size, 0, 0)
            return read >= 0 ? String(bytes: buffer.prefix(read), encoding: .utf8) : nil
        }
    }

    // MARK: Move and copy

    @Test func filesMovedIntoAnotherFolderAreThereAndNoLongerInTheFirst() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("a.jpg")
        let second = try fixture.file("b.jpg")

        let results = PhotoFileActions.move([first, second], to: fixture.target)

        #expect(results.map(\.source) == [first, second])
        #expect(results.allSatisfy { $0.succeeded })
        #expect(results.map { $0.destination?.lastPathComponent } == ["a.jpg", "b.jpg"])
        #expect(!exists(first) && !exists(second))
        #expect(exists(fixture.target.appendingPathComponent("a.jpg")))
        #expect(exists(fixture.target.appendingPathComponent("b.jpg")))
    }

    @Test func aNameAlreadyTakenIsNeverOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let taken = try fixture.file("IMG_0042.jpg", in: fixture.target, contents: "old one")
        let incoming = try fixture.file("IMG_0042.jpg", contents: "new one")

        let first = PhotoFileActions.move([incoming], to: fixture.target)
        let again = try fixture.file("IMG_0042.jpg", contents: "newer one")
        let second = PhotoFileActions.copy([again], to: fixture.target)

        #expect(first.first?.destination?.lastPathComponent == "IMG_0042 2.jpg")
        #expect(second.first?.destination?.lastPathComponent == "IMG_0042 3.jpg")
        #expect(try text(taken) == "old one")
        #expect(try text(fixture.target.appendingPathComponent("IMG_0042 2.jpg")) == "new one")
        #expect(try text(fixture.target.appendingPathComponent("IMG_0042 3.jpg")) == "newer one")
    }

    @Test func aFileWithoutExtensionGetsTheNumberAtTheEnd() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("notes", in: fixture.target)
        let incoming = try fixture.file("notes")

        let results = PhotoFileActions.copy([incoming], to: fixture.target)

        #expect(results.first?.destination?.lastPathComponent == "notes 2")
    }

    @Test func aFileMovedIntoItsOwnFolderStaysAndSucceeds() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")

        let results = PhotoFileActions.move([photo], to: fixture.source)

        #expect(results == [FileActionResult(source: photo, destination: photo)])
        #expect(try text(photo) == "pixels")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.source.path) == ["a.jpg"])
    }

    @Test func aCopyLeavesTheOriginalAndCarriesItsExtendedAttributes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")
        setAttribute("adjustments", on: photo)

        let results = PhotoFileActions.copy([photo], to: fixture.target)

        let copy = try #require(results.first?.destination)
        #expect(exists(photo))
        #expect(try text(copy) == "pixels")
        #expect(attribute(on: copy) == "adjustments")
    }

    // MARK: Duplicate and rename

    @Test func aDuplicateSitsBesideTheOriginalWithItsAttributes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")
        setAttribute("adjustments", on: photo)

        let first = try #require(PhotoFileActions.duplicate([photo], suffix: "copia").first?.destination)
        let second = try #require(PhotoFileActions.duplicate([photo], suffix: "copia").first?.destination)

        #expect(first.lastPathComponent == "a copia.jpg" && second.lastPathComponent == "a copia 2.jpg")
        #expect(first.deletingLastPathComponent().path == fixture.source.path)
        #expect(try text(first) == "pixels" && exists(photo))
        #expect(attribute(on: first) == "adjustments")
    }

    @Test func aRenamedFileKeepsItsExtensionAndAttributes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")
        setAttribute("adjustments", on: photo)

        let result = PhotoFileActions.rename(photo, to: "  Tramonto  ")

        let renamed = try #require(result.destination)
        #expect(renamed.lastPathComponent == "Tramonto.jpg" && !exists(photo))
        #expect(attribute(on: renamed) == "adjustments")
    }

    @Test func aRenameNeverOverwritesAnotherFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")
        let other = try fixture.file("b.jpg", contents: "other")

        let result = PhotoFileActions.rename(photo, to: "b")

        #expect(!result.succeeded && exists(photo))
        #expect(try text(other) == "other")
    }

    @Test func aRenameOnlyInCaseIsARename() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")

        let result = PhotoFileActions.rename(photo, to: "A")

        #expect(result.succeeded && result.destination?.lastPathComponent == "A.jpg")
    }

    @Test func namesThatCannotBeAFileNameAreRefused() {
        #expect(PhotoFileActions.isFileName("Tramonto 2"))
        for name in ["", "   ", ".hidden", "a/b", "a:b"] {
            #expect(!PhotoFileActions.isFileName(name))
        }
    }

    @Test func aMoveCarriesTheExtendedAttributes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")
        setAttribute("adjustments", on: photo)

        let results = PhotoFileActions.move([photo], to: fixture.target)

        let moved = try #require(results.first?.destination)
        #expect(!exists(photo))
        #expect(attribute(on: moved) == "adjustments")
    }

    @Test func aFileThatDoesNotExistFailsWhileTheOthersSucceed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let before = try fixture.file("a.jpg")
        let missing = fixture.source.appendingPathComponent("missing.jpg")
        let after = try fixture.file("c.jpg")

        let results = PhotoFileActions.move([before, missing, after], to: fixture.target)

        #expect(results.map(\.succeeded) == [true, false, true])
        #expect(results[1].destination == nil)
        #expect(results[1].error != nil)
        #expect(exists(fixture.target.appendingPathComponent("c.jpg")))
    }

    @Test func movingIntoAFolderThatDoesNotExistFailsForEveryFileAndCreatesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("a.jpg")
        let second = try fixture.file("b.jpg")
        let nowhere = fixture.root.appendingPathComponent("nowhere")

        let results = PhotoFileActions.move([first, second], to: nowhere)

        #expect(results.count == 2)
        #expect(results.allSatisfy { !$0.succeeded && $0.destination == nil })
        #expect(!exists(nowhere))
        #expect(exists(first) && exists(second))
    }

    // MARK: Trash

    @Test func aTrashedFileIsGoneFromItsFolder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")

        let results = PhotoFileActions.trash([photo])

        #expect(results.first?.succeeded == true)
        #expect(!exists(photo))
        if let trashed = results.first?.destination {
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    // MARK: Tags

    @Test func tagsAddedAreReadBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")

        let results = PhotoFileActions.addTag("Red", to: [photo])

        #expect(results.allSatisfy { $0.succeeded })
        #expect(PhotoFileActions.tags(of: photo) == ["Red"])
    }

    @Test func aSecondTagKeepsTheFirst() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")

        _ = PhotoFileActions.addTag("Red", to: [photo])
        _ = PhotoFileActions.addTag("Keeper", to: [photo])

        #expect(PhotoFileActions.tags(of: photo) == ["Red", "Keeper"])
    }

    @Test func removingATagKeepsTheOther() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")
        _ = PhotoFileActions.addTag("Red", to: [photo])
        _ = PhotoFileActions.addTag("Keeper", to: [photo])

        let results = PhotoFileActions.removeTag("Red", from: [photo])

        #expect(results.allSatisfy { $0.succeeded })
        #expect(PhotoFileActions.tags(of: photo) == ["Keeper"])
    }

    @Test func addingATagTwiceKeepsOne() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")

        _ = PhotoFileActions.addTag("Red", to: [photo])
        let again = PhotoFileActions.addTag("Red", to: [photo])

        #expect(again.allSatisfy { $0.succeeded })
        #expect(PhotoFileActions.tags(of: photo) == ["Red"])
    }

    @Test func removingATagAFileLacksSucceedsAndChangesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let photo = try fixture.file("a.jpg")
        _ = PhotoFileActions.addTag("Keeper", to: [photo])

        let results = PhotoFileActions.removeTag("Red", from: [photo])

        #expect(results.allSatisfy { $0.succeeded })
        #expect(PhotoFileActions.tags(of: photo) == ["Keeper"])
    }

    @Test func aTagCarriedByTwoOfThreeFilesIsCountedAsTwo() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let one = try fixture.file("a.jpg")
        let two = try fixture.file("b.jpg")
        let three = try fixture.file("c.jpg")
        _ = PhotoFileActions.addTag("Red", to: [one, two])
        _ = PhotoFileActions.addTag("Keeper", to: [three])

        let counts = PhotoFileActions.tags(ofAll: [one, two, three])

        #expect(counts == ["Red": 2, "Keeper": 1])
    }

    @Test func aFileThatCannotBeReadHasNoTags() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("alteralux-missing-\(UUID().uuidString).jpg")

        #expect(PhotoFileActions.tags(of: missing).isEmpty)
        #expect(PhotoFileActions.addTag("Red", to: [missing]).allSatisfy { !$0.succeeded })
    }
}
