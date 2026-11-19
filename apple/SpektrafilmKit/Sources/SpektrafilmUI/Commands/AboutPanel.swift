import AppKit

/// The standard About panel, with credits to the projects the app builds on.
@MainActor
enum AboutPanel {
    /// Font size of the credits, in points (the size AppKit uses for small text).
    private static let creditsFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    static let repositoryURL = URL(string: "https://github.com/davidelarocca/spektrafilm-macos")!
    static let upstreamURL = URL(string: "https://github.com/andreavolpato/spektrafilm")!

    static func show() {
        // One localized string: the backslashes only wrap the source line.
        let localized = AttributedString(
            localized: """
            Film modeling powered by [spektrafilm](https://github.com/andreavolpato/spektrafilm) by Andrea Volpato. \
            Rust engine: [spektrafilm-rs](https://github.com/turbasvin/spektrafilm-rs) by turbasvin. \
            Free software under the GNU GPL v3.
            """,
        )
        let credits = NSMutableAttributedString(attributedString: NSAttributedString(localized))
        let everything = NSRange(location: 0, length: credits.length)
        credits.addAttribute(.font, value: creditsFont, range: everything)
        credits.addAttribute(.foregroundColor, value: NSColor.labelColor, range: everything)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate()
    }
}
