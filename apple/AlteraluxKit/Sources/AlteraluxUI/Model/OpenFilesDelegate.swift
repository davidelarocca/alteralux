import AppIntents
import AppKit

/// Receives what the system hands to the app: a selection opened from the Finder, files dropped
/// on the Dock icon, `open -a`, and the photos sent from the Finder's "Develop with alteralux…"
/// (a Services entry, declared in the app's Info.plist).
///
/// It holds the app's model from launch, before any window: the main window opens only when the
/// app is opened, not when the Finder starts it to develop photos. Started that way, the app
/// stays out of sight, without a window or a Dock icon, and quits once the photos are developed.
///
/// SwiftUI's `onOpenURL` delivers only one file of such a request, so the app
/// takes them from AppKit, which hands over all of them at once.
@MainActor
public final class OpenFilesDelegate: NSObject, NSApplicationDelegate {
    public let model: AppModel
    /// Whether the system started the app to develop photos from the Finder, and nothing has
    /// shown it since.
    private(set) var isOutOfSight = false
    /// Whether the app's window was opened since launch.
    private var hasShownTheApp = false
    /// The latest photos sent to "Develop with alteralux…", being developed.
    private(set) var workflowRequest: Task<Void, Never>?

    /// The app's delegate, with the app's model, which the Shortcuts action uses too.
    override public init() {
        let model = AppModel()
        self.model = model
        super.init()
        AppDependencyManager.shared.add(dependency: model)
    }

    /// A delegate for `model`, for tests.
    init(model: AppModel) {
        self.model = model
        super.init()
    }

    public func applicationWillFinishLaunching(_: Notification) {
        // Set before launching ends, so a request that launched the app reaches it.
        NSApplication.shared.servicesProvider = self
    }

    /// Opened by the user, the app shows its window. Started by the system to develop photos
    /// from the Finder, it stays out of sight, without a Dock icon: their request arrives before
    /// launching ends. Photos opened from the Finder have already shown it.
    public func applicationDidFinishLaunching(_: Notification) {
        guard workflowRequest == nil else {
            isOutOfSight = !hasShownTheApp
            if isOutOfSight {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
            return
        }
        // The menu commands, which open the window, are made as launching ends.
        Task { showApp() }
    }

    /// A click on the Dock icon, or the app opened again, with no window: the main window.
    public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showApp()
        }
        return false
    }

    public func application(_: NSApplication, open urls: [URL]) {
        showApp()
        model.take(urls)
    }

    /// "Develop with alteralux…": the photos selected in the Finder, developed with a workflow,
    /// out of sight. The name is the `NSMessage` of the entry in Info.plist.
    @objc public func developWithWorkflow(
        _ pasteboard: NSPasteboard, userData _: String?, error _: AutoreleasingUnsafeMutablePointer<NSString?>,
    ) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        let previous = workflowRequest
        workflowRequest = Task {
            await previous?.value
            await model.developWithWorkflow(handedOver: urls)
            quitIfOutOfSight()
        }
    }

    private func showApp() {
        hasShownTheApp = true
        isOutOfSight = false
        model.showApp()
    }

    /// Quits the app the system started out of sight, once the photos are developed and nothing
    /// has shown it.
    private func quitIfOutOfSight() {
        let hasWindow = NSApplication.shared.windows.contains { $0.isVisible && $0.canBecomeMain }
        guard isOutOfSight, !hasWindow, !model.isExporting else { return }
        NSApplication.shared.terminate(nil)
    }
}
