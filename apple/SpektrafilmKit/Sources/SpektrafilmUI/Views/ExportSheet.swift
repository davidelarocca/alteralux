import SpektrafilmKit
import SwiftUI

/// Export options, shown before the save panel.
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Width of the sheet, in points.
    static let width: CGFloat = 420

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Form {
                Picker("Format", selection: $model.exportOptions.format) {
                    Text("JPEG").tag(ExportOptions.Format.jpeg)
                    Text("HEIC (10-bit)").tag(ExportOptions.Format.heic)
                    Text("TIFF (16-bit)").tag(ExportOptions.Format.tiff)
                    Text("PNG (16-bit)").tag(ExportOptions.Format.png)
                }
                Picker("Color profile", selection: $model.exportOptions.colorProfile) {
                    Text("sRGB").tag(ExportOptions.ColorProfile.sRGB)
                    Text("Display P3").tag(ExportOptions.ColorProfile.displayP3)
                }
                if model.exportOptions.format == .jpeg || model.exportOptions.format == .heic {
                    Slider(value: $model.exportOptions.quality, in: 0.5 ... 1) {
                        Text("Quality")
                    }
                }
                Toggle("Include camera metadata", isOn: $model.exportOptions.copiesMetadata)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    dismiss()
                    Task { await model.export() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: Self.width)
    }
}
