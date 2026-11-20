import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxKit

struct LibraryFoldersTests {
    @Test func aFolderAddedIsRememberedAfterARelaunch() async throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeFolder("Pictures")
        let storeURL = fixture.root.appendingPathComponent("support/library.plist")
        let firstLibrary = LibraryFolders(storeURL: storeURL)

        let added = try await firstLibrary.add(folderURL)
        #expect(await firstLibrary.folders() == [added])

        let secondLibrary = LibraryFolders(storeURL: storeURL)
        let loaded = await secondLibrary.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == added.id)
        #expect(loaded.first?.url.resolvingSymlinksInPath() == folderURL.resolvingSymlinksInPath())
        #expect(loaded.first?.isAvailable == true)
    }

    @Test func addingTheSameFolderTwiceKeepsOneEntry() async throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeFolder("Pictures")
        let library = LibraryFolders(storeURL: fixture.root.appendingPathComponent("library.plist"))

        let first = try await library.add(folderURL)
        let second = try await library.add(folderURL)

        #expect(first.id == second.id)
        #expect(await library.folders().count == 1)
    }

    @Test func aRemovedFolderIsGoneAfterReloading() async throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeFolder("Pictures")
        let storeURL = fixture.root.appendingPathComponent("library.plist")
        let library = LibraryFolders(storeURL: storeURL)
        let added = try await library.add(folderURL)

        await library.remove(added.id)

        let reloaded = await LibraryFolders(storeURL: storeURL).load()
        #expect(reloaded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folderURL.path))
    }

    @Test func aDeletedFolderLoadsAsUnavailable() async throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeFolder("Pictures")
        let storeURL = fixture.root.appendingPathComponent("library.plist")
        let library = LibraryFolders(storeURL: storeURL)
        let added = try await library.add(folderURL)
        try FileManager.default.removeItem(at: folderURL)

        let loaded = await LibraryFolders(storeURL: storeURL).load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == added.id)
        #expect(loaded.first?.url == folderURL)
        #expect(loaded.first?.isAvailable == false)
    }

    @Test func addingAFileThrows() async throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let fileURL = fixture.root.appendingPathComponent("photo.jpg")
        try Data().write(to: fileURL)
        let library = LibraryFolders(storeURL: fixture.root.appendingPathComponent("library.plist"))

        await #expect(throws: (any Error).self) {
            try await library.add(fileURL)
        }
    }

    @Test func aFolderTreeCountsPhotosAndSkipsHiddenItemsAndPackages() throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let album10 = try fixture.makeFolder("Pictures/Album 10")
        let album2 = try fixture.makeFolder("Pictures/Album 2")
        let nested = try fixture.makeFolder("Pictures/Album 10/Nested")
        let app = try fixture.makeFolder("Pictures/Editor.app")
        let photoLibrary = try fixture.makeFolder("Pictures/Archive.photoslibrary")
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("Pictures/Linked Album"),
            withDestinationURL: album2,
        )
        try fixture.writeFile("cover.jpg", in: "Pictures")
        try fixture.writeFile(".hidden.jpg", in: "Pictures")
        try fixture.writeFile("ten.tif", in: "Pictures/Album 10")
        try fixture.writeFile("two.png", in: "Pictures/Album 2")
        try fixture.writeFile("nested.dng", in: "Pictures/Album 10/Nested")
        try fixture.writeFile("inside.jpg", in: "Pictures/Editor.app")
        try fixture.writeFile("inside.jpg", in: "Pictures/Archive.photoslibrary")

        let tree = try FolderContents.tree(of: fixture.root.appendingPathComponent("Pictures"))

        #expect(tree.photoCount == 1)
        #expect(tree.children.map(\.name) == ["Album 2", "Album 10"])
        #expect(tree.children.map(\.photoCount) == [1, 1])
        #expect(tree.children.last?.children.map(\.name) == ["Nested"])
        #expect(tree.children.last?.children.first?.photoCount == 1)
        #expect(!tree.children.contains { $0.url == app || $0.url == photoLibrary })
        #expect(!tree.children.contains { $0.name == "Linked Album" })
        #expect(tree.children.first?.url.resolvingSymlinksInPath() == album2.resolvingSymlinksInPath())
        #expect(tree.children.last?.url.resolvingSymlinksInPath() == album10.resolvingSymlinksInPath())
        #expect(
            tree.children.last?.children.first?.url.resolvingSymlinksInPath()
                == nested.resolvingSymlinksInPath(),
        )
    }

    @Test func photosAreImagesSortedLikeTheFinderAndIncludeRawFiles() throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let pictures = try fixture.makeFolder("Pictures")
        try fixture.writeFile("IMG_10.jpg", in: "Pictures")
        try fixture.writeFile("IMG_2.jpg", in: "Pictures")
        try fixture.writeFile("a.dng", in: "Pictures")
        try fixture.writeFile("z.png", in: "Pictures")
        try fixture.writeFile("notes.txt", in: "Pictures")
        try fixture.writeFile(".hidden.jpg", in: "Pictures")
        _ = try fixture.makeFolder("Pictures/Not a photo.jpg")
        try FileManager.default.createSymbolicLink(
            at: pictures.appendingPathComponent("alias.jpg"),
            withDestinationURL: pictures.appendingPathComponent("IMG_2.jpg"),
        )

        let photos = try FolderContents.photos(in: pictures)

        #expect(photos.map(\.lastPathComponent) == ["a.dng", "IMG_2.jpg", "IMG_10.jpg", "z.png"])
        #expect(photos.allSatisfy { url in
            let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            return contentType.map { $0.conforms(to: .image) } ?? false
        })
    }

    @Test func aWatcherReportsAFileCreatedInASubfolder() async throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let nested = try fixture.makeFolder("Pictures/Album")
        let watcher = FolderWatcher(url: fixture.root.appendingPathComponent("Pictures"))

        try Data().write(to: nested.appendingPathComponent("new.jpg"))

        #expect(await receivesChange(in: watcher.changes, within: .seconds(5)))
        watcher.stop()
    }

    @Test func aWatcherCoalescesAFileCreationBurst() async throws {
        let fixture = try FolderFixture()
        defer { fixture.remove() }
        let pictures = try fixture.makeFolder("Pictures")
        let watcher = FolderWatcher(url: pictures)
        let eventCount = Task {
            var count = 0
            for await _ in watcher.changes {
                count += 1
            }
            return count
        }

        for index in 0 ..< 30 {
            try Data().write(to: pictures.appendingPathComponent("photo-\(index).jpg"))
        }
        try await Task.sleep(for: .seconds(2))
        watcher.stop()

        #expect(await eventCount.value == 1)
    }

    private func receivesChange(in stream: AsyncStream<Void>, within duration: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: duration)
                return false
            }
            let received = await group.next() ?? false
            group.cancelAll()
            return received
        }
    }
}

private struct FolderFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-folders-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeFolder(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func writeFile(_ name: String, in relativePath: String) throws {
        let folder = root.appendingPathComponent(relativePath, isDirectory: true)
        try Data().write(to: folder.appendingPathComponent(name))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
