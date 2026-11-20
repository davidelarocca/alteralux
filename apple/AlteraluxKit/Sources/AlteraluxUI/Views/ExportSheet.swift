import AlteraluxKit
import DesignSystem
import SwiftUI

/// Export options: for the photo on screen, shown before the save panel; for the selected photos
/// of the library, with where they go, and then the one progress of the whole export.
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The long sides offered for the exported photo, in pixels, after the original size.
    static let longSides = [4096, 3072, 2048, 1600]

    var body: some View {
        Group {
            if let progress = model.batchExport {
                FormSheet(
                    Text("Developing"), confirm: nil,
                    cancel: SheetAction(Text("Stop")) { model.cancelExport() },
                ) {
                    ProgressView(value: Double(progress.position - 1), total: Double(progress.total)) {
                        Text("\(Text("\(progress.position) of \(progress.total)")) · \(Text(verbatim: progress.name))")
                            .font(Typography.technical)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                options
            }
        }
        // An export in progress is not left behind by Escape.
        .interactiveDismissDisabled(model.batchExport != nil)
        .alert(
            "\(model.exportWaiting?.existing ?? 0) of these photos were already exported",
            isPresented: isWaiting,
        ) {
            Button("Replace") { Task { await model.resumeExport(.replace) } }
            Button("Keep Both") { Task { await model.resumeExport(.keepBoth) } }
            Button("Skip Them") { Task { await model.resumeExport(.skip) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their files are in the destination folder. Replace them with the new ones, keep both, or skip the photos that are already there?")
        }
    }

    private var isWaiting: Binding<Bool> {
        Binding(
            get: { model.exportWaiting != nil },
            set: {
                if !$0 {
                    model.exportWaiting = nil
                }
            },
        )
    }

    /// Whether the sheet is for several photos of the library, and not for the one on screen.
    private var isForSelection: Bool {
        !model.photosToExport.isEmpty
    }

    private var title: Text {
        isForSelection ? Text("Export \(model.photosToExport.count) Photos") : Text("Export the Photo")
    }

    /// For the photo on screen the sheet goes, and the save panel asks where; for several
    /// photos it stays, and shows how far the export is.
    private var export: SheetAction {
        if isForSelection {
            SheetAction(Text("Export")) {
                Task { await model.exportPhotos() }
            }
        } else {
            SheetAction(Text("Export…")) {
                dismiss()
                Task { await model.export() }
            }
        }
    }

    private var options: some View {
        @Bindable var model = model

        return FormSheet(title, confirm: export, cancel: SheetAction(Text("Cancel")) { dismiss() }) {
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
            Picker("Size", selection: $model.exportOptions.longSide) {
                Text("Original").tag(Int?.none)
                ForEach(Self.longSides, id: \.self) { side in
                    Text("\(side) px on the long side").tag(Int?.some(side))
                }
            }
            Toggle("Include camera metadata", isOn: $model.exportOptions.copiesMetadata)
            if isForSelection {
                destination
            }
        }
    }

    /// Where several photos go: beside each original, or into one folder asked for at the start.
    private var destination: some View {
        @Bindable var model = model

        return Section {
            Picker("Destination", selection: $model.exportsBesideOriginals) {
                Text("Beside the originals").tag(true)
                Text("Another folder…").tag(false)
            }
        } footer: {
            Group {
                if model.exportsBesideOriginals {
                    Text(
                        "The files go into “\(AppModel.developedFolderName)”, beside the originals. If some are already there, you are asked what to do.",
                    )
                } else {
                    Text("You choose the folder when the export starts. If some files are already there, you are asked what to do.")
                }
            }
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
