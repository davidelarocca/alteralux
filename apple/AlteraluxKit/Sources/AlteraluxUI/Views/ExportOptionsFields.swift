import AlteraluxKit
import DesignSystem
import SwiftUI

/// The rows of a form that choose how developed photos are written: format, color profile,
/// quality, size and metadata. The same in the export sheet and in a workflow.
struct ExportOptionsFields: View {
    @Binding var options: ExportOptions

    /// The long sides offered for the exported photo, in pixels, after the original size.
    static let longSides = [4096, 3072, 2048, 1600]

    var body: some View {
        WindowPopUp("Format", selection: $options.format, options: [
            WindowPopUpOption(.jpeg, title: String(localized: "JPEG")),
            WindowPopUpOption(.heic, title: String(localized: "HEIC (10-bit)")),
            WindowPopUpOption(.tiff, title: String(localized: "TIFF (16-bit)")),
            WindowPopUpOption(.png, title: String(localized: "PNG (16-bit)")),
        ])
        WindowPopUp("Color profile", selection: $options.colorProfile, options: [
            WindowPopUpOption(.sRGB, title: String(localized: "sRGB")),
            WindowPopUpOption(.displayP3, title: String(localized: "Display P3")),
        ])
        if options.format == .jpeg || options.format == .heic {
            Slider(value: $options.quality, in: 0.5 ... 1) {
                Text("Quality")
            }
        }
        WindowPopUp(
            "Size", selection: $options.longSide,
            options: [WindowPopUpOption(Int?.none, title: String(localized: "Original"))]
                + Self.longSides.map { side in
                    WindowPopUpOption(Int?.some(side), title: String(localized: "\(side) px on the long side"))
                },
        )
        Toggle("Include camera metadata", isOn: $options.copiesMetadata)
    }
}
