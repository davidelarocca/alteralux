import AppKit

/// The standard About panel, with credits to the projects the app builds on.
@MainActor
enum AboutPanel {
    static let repositoryURL = URL(string: "https://github.com/davidelarocca/spektrafilm-macos")!
    static let upstreamURL = URL(string: "https://github.com/andreavolpato/spektrafilm")!

    static func show() {
        var credits = AttributedString(
            localized:
                "Film modeling powered by [spektrafilm](https://github.com/andreavolpato/spektrafilm) by Andrea Volpato. Rust engine: [spektrafilm-rs](https://github.com/turbasvin/spektrafilm-rs) by turbasvin. Free software under the GNU GPL v3."
        )
        credits.appKit.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        credits.appKit.foregroundColor = .labelColor
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(credits)
        ])
        NSApplication.shared.activate()
    }
}
