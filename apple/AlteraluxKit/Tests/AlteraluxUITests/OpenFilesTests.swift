import AppKit
import Foundation
import Testing
@testable import AlteraluxUI

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
        let delegate = OpenFilesDelegate(model: model)

        delegate.application(NSApplication.shared, open: files)

        #expect(model.photos.map(\.url) == files)
        #expect(model.selection?.url == files[0])
    }

    @Test func filesOpenedFromTheFinderOpenTheWindow() throws {
        let files = try WindowedTests.writeTestPictures(count: 2)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let model = model()
        var windows = 0
        model.openMainWindow = { windows += 1 }
        let delegate = OpenFilesDelegate(model: model)

        // The model is there before any window: the photos are opened at once, and the window
        // the app opens shows them.
        delegate.application(NSApplication.shared, open: files)

        #expect(model.photos.map(\.url) == files)
        #expect(windows == 1)
    }

    @Test func aSecondRequestAddsToTheStrip() throws {
        let files = try WindowedTests.writeTestPictures(count: 3)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let model = model()
        let delegate = OpenFilesDelegate(model: model)

        delegate.application(NSApplication.shared, open: [files[0]])
        delegate.application(NSApplication.shared, open: [files[0], files[1], files[2]])

        #expect(model.photos.map(\.url) == files)
    }
}
