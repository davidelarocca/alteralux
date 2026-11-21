import AlteraluxKit
import AppKit
import Foundation
import Testing
@testable import AlteraluxUI

/// Photos handed over from outside the app to develop with a workflow: from the Finder's
/// "Develop with alteralux…" and from the Shortcuts action.
@MainActor
struct HandedOverTests {
    /// A recipe's fixture with a workflow of small PNG files for it, and photos in a folder of
    /// their own, outside the library. The caller removes both folders.
    private struct Outside {
        let fixture: WorkflowTests.Fixture
        let workflow: Workflow
        let photos: [URL]

        @MainActor
        init(destination: Workflow.Destination = .besideOriginals(folderName: "Out")) async throws {
            fixture = try await WorkflowTests.Fixture(photos: 1)
            var workflow = fixture.model.newWorkflow(for: fixture.recipe)
            workflow.options.longSide = 64
            workflow.options.format = .png
            workflow.destination = destination
            await fixture.model.save(workflow)
            self.workflow = try #require(fixture.model.workflows.first)
            photos = try WindowedTests.writeTestPictures(count: 2)
        }

        var folder: URL {
            photos[0].deletingLastPathComponent()
        }

        func remove() {
            fixture.remove()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// A pasteboard of its own holding `urls`, as the Finder sends them to a Services entry.
    private func pasteboard(with urls: [URL]) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("alteralux-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        return pasteboard
    }

    @Test func photosSentFromTheFinderOpenTheWorkflowSheetWithoutJoiningTheLibrary() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model
        let note = outside.folder.appendingPathComponent("Notes.txt")
        try Data("not a photo".utf8).write(to: note)
        let libraryPhotos = model.library.photos
        let strip = model.photos.map(\.url)

        // Sent before the window is there: kept until the model comes.
        let delegate = OpenFilesDelegate()
        let sent = pasteboard(with: outside.photos + [note])
        var error: NSString?
        delegate.developWithWorkflow(sent, userData: nil, error: &error)
        #expect(!model.isExportPresented)
        delegate.attach(model)

        #expect(model.isExportPresented && model.exportsWithWorkflow)
        #expect(model.photosToExport == outside.photos)
        #expect(model.chosenWorkflow == outside.workflow)
        #expect(model.library.photos == libraryPhotos && model.photos.map(\.url) == strip)
        sent.releaseGlobally()
    }

    @Test func withNoWorkflowYetAnAlertLeadsToMakingOne() async throws {
        let fixture = try await WorkflowTests.Fixture(photos: 1)
        defer { fixture.remove() }
        let photos = try WindowedTests.writeTestPictures(count: 1)
        defer { try? FileManager.default.removeItem(at: photos[0].deletingLastPathComponent()) }
        #expect(fixture.model.workflows.isEmpty)

        fixture.model.developWithWorkflow(handedOver: photos)

        #expect(fixture.model.isWorkflowNeeded && !fixture.model.isExportPresented)
        #expect(fixture.model.photosToExport == photos)
    }

    @Test func onlyFilesThatAreNotPhotosSayWhy() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model
        let note = outside.folder.appendingPathComponent("Notes.txt")
        try Data("not a photo".utf8).write(to: note)

        model.developWithWorkflow(handedOver: [note])

        #expect(!model.isExportPresented && model.alertMessage != nil)
    }

    @Test func aFolderOutsideTheLibraryIsAskedForOnce() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model

        // The library's own folders need nothing.
        #expect(await model.foldersNeedingPermission(for: model.library.photos).isEmpty)
        let needed = await model.foldersNeedingPermission(for: outside.photos)
        #expect(needed.map(\.lastPathComponent) == [outside.folder.lastPathComponent])

        // Once allowed, the folder and the ones inside it need nothing, at the next launch too.
        try await model.writableFolders.add(outside.folder)
        #expect(await model.foldersNeedingPermission(for: outside.photos).isEmpty)
        let next = AppModel(
            dataDirectory: WindowedTests.engineData,
            editsDirectory: outside.fixture.folder.appendingPathComponent("support"),
        )
        _ = await next.writableFolders.load()
        #expect(await next.foldersNeedingPermission(for: outside.photos).isEmpty)
    }

    @Test func aFolderHoldsOnlyWhatIsInsideIt() {
        let folder = URL(fileURLWithPath: "/Photos/Trip", isDirectory: true)
        #expect(AppModel.isInside(folder, folder))
        #expect(AppModel.isInside(URL(fileURLWithPath: "/Photos/Trip/Day 1"), folder))
        #expect(!AppModel.isInside(URL(fileURLWithPath: "/Photos/Trip 2"), folder))
        #expect(!AppModel.isInside(URL(fileURLWithPath: "/Photos"), folder))
    }

    @Test func photosSentFromTheFinderAreWrittenBesideTheirOriginals() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model
        try await model.writableFolders.add(outside.folder)

        model.developWithWorkflow(handedOver: outside.photos)
        await model.developWithWorkflow()

        #expect(model.alertMessage == nil && !model.isExportPresented)
        let written = try FileManager.default.contentsOfDirectory(atPath: outside.folder.appendingPathComponent("Out").path)
        #expect(written.count == 2 && written.allSatisfy { $0.hasSuffix(".png") })
    }

    @Test func aShortcutGetsTheFilesBack() async throws {
        let outside = try await Outside()
        defer { outside.remove() }
        let model = outside.fixture.model
        let scratch = outside.folder.appendingPathComponent("Scratch")

        let files = try await model.developForShortcut(outside.photos, workflow: outside.workflow.id, scratch: scratch)

        #expect(files.count == 2 && files.allSatisfy { !$0.data.isEmpty && $0.type == .png })
        #expect(try Set(files.map(\.name)) == Set(FileManager.default.contentsOfDirectory(atPath: scratch.path)))
        // Nothing is written beside the photos: Shortcuts may have handed over copies.
        #expect(!FileManager.default.fileExists(atPath: outside.folder.appendingPathComponent("Out").path))

        // A run again keeps the earlier files and gives back only the new ones.
        let again = try await model.developForShortcut(outside.photos, workflow: outside.workflow.id, scratch: scratch)
        #expect(Set(again.map(\.name)).isDisjoint(with: files.map(\.name)))

        await #expect(throws: HandedOverError.workflowMissing) {
            try await model.developForShortcut(outside.photos, workflow: UUID(), scratch: scratch)
        }
    }

    @Test func aShortcutWithAFolderOfItsOwnLeavesTheFilesThere() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let outside = try await Outside(destination: .folder(FolderBookmark(for: output)))
        defer { outside.remove() }
        let model = outside.fixture.model
        let scratch = outside.folder.appendingPathComponent("Scratch")

        let files = try await model.developForShortcut(outside.photos, workflow: outside.workflow.id, scratch: scratch)

        #expect(try Set(files.map(\.name)) == Set(FileManager.default.contentsOfDirectory(atPath: output.path)))
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    @Test func shortcutsSeeTheWorkflowsByName() async throws {
        let outside = try await Outside()
        defer { outside.remove() }

        let choices = await outside.fixture.model.workflowChoices()

        #expect(choices.map(\.id) == [outside.workflow.id])
        #expect(choices.first?.name == outside.workflow.name && choices.first?.summary.contains("PNG") == true)
    }
}
