import AlteraluxKit
import DesignSystem
import SwiftUI

/// Export options: for the photo on screen, shown before the save panel; for the selected photos
/// of the library, with where they go, or the workflow they are developed with; and then the one
/// progress of the whole export.
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

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
            } else if model.exportsWithWorkflow {
                WorkflowRunForm()
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
            Button("Replace") { resume(.replace) }
            Button("Keep Both") { resume(.keepBoth) }
            Button("Skip Them") { resume(.skip) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their files are in the destination folder, some perhaps with another film or format. Replacing moves the old files to the Trash.")
        }
    }

    /// Goes on with the export that waits, taken now: closing, the alert lets it go.
    private func resume(_ policy: ExistingFilePolicy) {
        guard let waiting = model.exportWaiting else { return }
        Task { await model.resumeExport(waiting, policy) }
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
            ExportOptionsFields(options: $model.exportOptions)
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
