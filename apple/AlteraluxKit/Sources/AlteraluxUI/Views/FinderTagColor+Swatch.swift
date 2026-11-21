import AlteraluxKit
import AppKit
import SwiftUI

extension FinderTagColor {
    /// The color the Finder draws this tag with: the system's own.
    var swatch: Color {
        switch self {
        case .gray: .gray
        case .green: .green
        case .purple: .purple
        case .blue: .blue
        case .yellow: .yellow
        case .red: .red
        case .orange: .orange
        }
    }

    /// The name of the color, as the Finder says it.
    var name: LocalizedStringResource {
        switch self {
        case .gray: "Gray"
        case .green: "Green"
        case .purple: "Purple"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .red: "Red"
        case .orange: "Orange"
        }
    }
}

extension FinderTag {
    /// The tag's dot for a menu, as the Finder shows it there: filled with the tag's color, or
    /// an empty circle for a tag without one. An image of its own: a menu draws symbols in one
    /// color.
    var menuDot: Image {
        let color = color.map { NSColor($0.swatch) }
        let side = Self.menuDotSide
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if let color {
                color.setFill()
                circle.fill()
            } else {
                NSColor.secondaryLabelColor.setStroke()
                circle.stroke()
            }
            return true
        }
        return Image(nsImage: image)
    }

    /// The side of a tag's dot in a menu, in points: as tall as the menu's text.
    private static let menuDotSide: CGFloat = 12
}
