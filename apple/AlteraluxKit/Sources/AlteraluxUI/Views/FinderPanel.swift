import AlteraluxKit
import AppKit
import DesignSystem
import SwiftUI

/// What the app asks about photos sent from the Finder, out of sight of its own windows: a small
/// panel at the center of the screen, drawn as the app's sheets are, for a choice to make; the
/// system's alert for something to say. The panel takes the keys without bringing the app, or
/// its windows, to the front.
@MainActor
enum FinderPanel {
    static func ask(_ question: FinderQuestion) async -> FinderAnswer {
        switch question {
        case let .run(photos, recipes, chosen):
            return await present { reply in
                FinderRecipeRun(photos: photos, recipes: recipes, chosen: chosen, reply: reply)
            }
        case let .noRecipe(photos):
            let opens = alert(
                title: String(localized: "Develop \(photos) Photos"),
                message: String(localized: "There is no recipe yet: open a photo in alteralux, give it the look you like and save it as a recipe."),
                buttons: [String(localized: "Open alteralux"), String(localized: "Cancel")],
            ) == .alertFirstButtonReturn
            return opens ? .openApp : .cancel
        case let .problem(message):
            alert(title: String(localized: "Something went wrong"), message: message, buttons: [String(localized: "OK")])
            return .cancel
        }
    }

    /// Shows `content` in the panel, which closes with the answer.
    private static func present(_ content: @escaping (@escaping (FinderAnswer) -> Void) -> some View) async -> FinderAnswer {
        await withCheckedContinuation { continuation in
            let panel = NSPanel(
                contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered, defer: false,
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                panel.standardWindowButton(button)?.isHidden = true
            }
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            let reply = Reply { answer in
                panel.close()
                continuation.resume(returning: answer)
            }
            // The panel takes the form's size, and follows it as rows come and go; the hosting
            // view sizes nothing itself, which loops when it drives a window (PITFALLS).
            let form = content(reply.send)
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: \.size) { size in
                    guard size.width > 0, size != panel.contentView?.frame.size else { return }
                    let frame = panel.frame
                    panel.setContentSize(size)
                    // Grown or shrunk downward, from where it was.
                    panel.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
                }
                // The panel has no title bar to make room for: the form starts at its top.
                .ignoresSafeArea()
            let host = NSHostingView(rootView: form)
            host.sizingOptions = []
            panel.contentView = host
            panel.setContentSize(host.fittingSize)
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The system's alert, on its own: the app comes to the front for it.
    @discardableResult
    private static func alert(title: String, message: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        NSApplication.shared.activate()
        return alert.runModal()
    }

    /// Answers once: the panel's buttons and keys may both try.
    private final class Reply {
        private var answer: ((FinderAnswer) -> Void)?

        init(_ answer: @escaping (FinderAnswer) -> Void) {
            self.answer = answer
        }

        func send(_ value: FinderAnswer) {
            answer?(value)
            answer = nil
        }
    }
}

/// The recipe that develops the photos sent from the Finder, among several, and the settings
/// it leaves open.
struct FinderRecipeRun: View {
    let photos: Int
    let recipes: [Recipe]
    let reply: (FinderAnswer) -> Void
    @State private var run: Recipe

    init(photos: Int, recipes: [Recipe], chosen: Recipe.ID?, reply: @escaping (FinderAnswer) -> Void) {
        self.photos = photos
        self.recipes = recipes
        self.reply = reply
        _run = State(initialValue: recipes.first { $0.id == chosen } ?? recipes[0])
    }

    var body: some View {
        FormSheet(
            Text("Develop \(photos) Photos"),
            confirm: SheetAction(Text("Develop"), isEnabled: AppModel.canWrite(run.files)) { reply(.run(run)) },
            cancel: SheetAction(Text("Cancel")) { reply(.cancel) },
        ) {
            RecipeRunSection(recipes: recipes, run: $run)
        }
    }
}

#Preview("Finder, a recipe that asks") {
    FinderRecipeRun(
        photos: 3,
        recipes: [
            Recipe(name: "Portra for the web", from: DevelopSettings(), files: RecipeFiles(asks: [.format, .destination])),
            Recipe(name: "Prints", from: DevelopSettings()),
        ],
        chosen: nil, reply: { _ in },
    )
}

#Preview("Finder, one recipe that asks") {
    FinderRecipeRun(
        photos: 1, recipes: [Recipe(name: "Portra at dusk", from: DevelopSettings(), files: RecipeFiles(asks: [.size]))],
        chosen: nil, reply: { _ in },
    )
}
