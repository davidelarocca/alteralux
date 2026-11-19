import AppKit

/// Receives the files the system asks the app to open: a selection opened from
/// the Finder, files dropped on the Dock icon, `open -a`.
///
/// SwiftUI's `onOpenURL` delivers only one file of such a request, so the app
/// takes them from AppKit, which hands over all of them at once.
@MainActor
public final class OpenFilesDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    /// Files that arrived before the model was attached: at launch the system
    /// can ask to open files before the window exists.
    private var pending: [URL] = []

    /// Gives the delegate the model to open files in, and opens the ones that
    /// arrived meanwhile.
    public func attach(_ model: AppModel) {
        self.model = model
        guard !pending.isEmpty else { return }
        model.open(pending)
        pending = []
    }

    public func application(_: NSApplication, open urls: [URL]) {
        if let model {
            model.open(urls)
        } else {
            pending += urls
        }
    }
}
