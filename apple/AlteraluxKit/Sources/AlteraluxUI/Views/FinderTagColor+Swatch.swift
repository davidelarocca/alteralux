import AlteraluxKit
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
}
