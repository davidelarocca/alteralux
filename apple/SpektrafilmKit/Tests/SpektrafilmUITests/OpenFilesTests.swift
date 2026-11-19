import AppKit
import Foundation
import Testing
@testable import SpektrafilmUI

/// Files the system asks the app to open, several at a time.
@MainActor
struct OpenFilesTests {
    private func model() -> AppModel {
        AppModel(dataDirectory: WindowedTests.engineData)
    }

    @Test func everyFileOfOneRequestIsOpened() throws {
        let files = try WindowedTests.writeTestPictures(count: 3)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let model = model()
        let delegate = OpenFilesDelegate()
        delegate.attach(model)

        delegate.application(NSApplication.shared, open: files)

        #expect(model.photos.map(\.url) == files)
        #expect(model.selection?.url == files[0])
    }

    @Test func filesThatArriveBeforeTheWindowAreKept() throws {
        let files = try WindowedTests.writeTestPictures(count: 2)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let model = model()
        let delegate = OpenFilesDelegate()

        delegate.application(NSApplication.shared, open: files)
        #expect(model.photos.isEmpty)
        delegate.attach(model)

        #expect(model.photos.map(\.url) == files)
    }

    @Test func aSecondRequestAddsToTheStrip() throws {
        let files = try WindowedTests.writeTestPictures(count: 3)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let model = model()
        let delegate = OpenFilesDelegate()
        delegate.attach(model)

        delegate.application(NSApplication.shared, open: [files[0]])
        delegate.application(NSApplication.shared, open: [files[0], files[1], files[2]])

        #expect(model.photos.map(\.url) == files)
    }
}
