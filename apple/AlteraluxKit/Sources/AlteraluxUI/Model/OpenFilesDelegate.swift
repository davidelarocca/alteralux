import AppKit

/// Receives the files the system hands to the app: a selection opened from the Finder, files
/// dropped on the Dock icon, `open -a`, and the photos sent from the Finder's
/// "Develop with alteralux…" (a Services entry, declared in the app's Info.plist).
///
/// SwiftUI's `onOpenURL` delivers only one file of such a request, so the app
/// takes them from AppKit, which hands over all of them at once.
@MainActor
public final class OpenFilesDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    /// Files that arrived before the model was attached: at launch the system
    /// can ask to open files before the window exists.
    private var pending: [URL] = []
    /// Photos sent to "Develop with alteralux…" before the model was attached, and the app
    /// that sent them.
    private var pendingForWorkflow: [URL] = []
    private var sender: NSRunningApplication?
    /// The latest photos sent to "Develop with alteralux…", being developed.
    private(set) var workflowRequest: Task<Void, Never>?

    /// Gives the delegate the model to open files in, and opens the ones that
    /// arrived meanwhile.
    public func attach(_ model: AppModel) {
        self.model = model
        if !pending.isEmpty {
            model.take(pending)
            pending = []
        }
        if !pendingForWorkflow.isEmpty {
            develop(pendingForWorkflow, in: model)
            pendingForWorkflow = []
        }
    }

    public func applicationWillFinishLaunching(_: Notification) {
        // Set before launching ends, so a request that launched the app reaches it.
        NSApplication.shared.servicesProvider = self
    }

    public func application(_: NSApplication, open urls: [URL]) {
        if let model {
            model.take(urls)
        } else {
            pending += urls
        }
    }

    /// "Develop with alteralux…": the photos selected in the Finder, to develop with a
    /// workflow. The name is the `NSMessage` of the entry in Info.plist.
    @objc public func developWithWorkflow(
        _ pasteboard: NSPasteboard, userData _: String?, error _: AutoreleasingUnsafeMutablePointer<NSString?>,
    ) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        // The Finder comes back to the front once the workflow is chosen.
        let front = NSWorkspace.shared.frontmostApplication
        sender = front == .current ? nil : front
        NSApplication.shared.activate()
        if let model {
            develop(urls, in: model)
        } else {
            pendingForWorkflow += urls
        }
    }

    private func develop(_ urls: [URL], in model: AppModel) {
        let sender = sender
        workflowRequest = Task { await model.developWithWorkflow(handedOver: urls, from: sender) }
    }
}
