import AppKit

/// The standard About panel, with credits to the projects the app builds on.
@MainActor
enum AboutPanel {
    static let repositoryURL = URL(string: "https://github.com/davidelarocca/spektrafilm-macos")!
    static let upstreamURL = URL(string: "https://github.com/andreavolpato/spektrafilm")!

    static func show() {
        let localized = AttributedString(
            localized:
                "Film modeling powered by [spektrafilm](https://github.com/andreavolpato/spektrafilm) by Andrea Volpato. Rust engine: [spektrafilm-rs](https://github.com/turbasvin/spektrafilm-rs) by turbasvin. Free software under the GNU GPL v3."
        )
        let credits = NSMutableAttributedString(localized)
        let everything = NSRange(location: 0, length: credits.length)
        credits.addAttribute(
            .font, value: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), range: everything)
        credits.addAttribute(.foregroundColor, value: NSColor.labelColor, range: everything)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate()
    }
}
