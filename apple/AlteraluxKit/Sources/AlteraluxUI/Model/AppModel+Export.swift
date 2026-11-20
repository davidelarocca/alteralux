import AlteraluxKit
import AppKit
import Foundation

// Export: the photo on screen to a file the user names, or the selected photos of the library in
// one go, each developed with its own adjustments.

/// How far the export of several photos is.
struct BatchExportProgress: Equatable {
    /// The position of the photo being developed, from 1.
    var position: Int
    let total: Int
    /// The name of the photo being developed.
    var name: String
}

/// An export of several photos that found files already written, and what it was about to do.
struct WaitingExport: Equatable {
    let photos: [URL]
    let destination: ExportDestination
    /// How many of the photos have their file there already.
    let existing: Int
}

extension AppModel {
    /// Whether there is something to export: in the library the selected photos, otherwise the
    /// photo on screen.
    var canPresentExport: Bool {
        showsLibrary ? canGiveLookToSelection && renderer != nil && !isExporting : canExport
    }

    /// Shows the export sheet, for the selected photos of the library or for the photo on screen.
    func presentExport() {
        guard canPresentExport else { return }
        photosToExport = showsLibrary ? selectedPhotos : []
        isExportPresented = true
    }

    // MARK: - One photo

    /// Asks where to save the developed photo, and writes it there.
    func export() async {
        guard let sources, !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportOptions.format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = exportFileName(for: sources.decoder.url, settings: settings)
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        await export(to: destination)
    }

    /// Develops the photo with the settings on screen, whole or at the size chosen, and writes
    /// it to `destination`.
    func export(to destination: URL) async {
        guard let sources, let renderer, !isExporting else { return }
        let url = sources.decoder.url
        let settings = settings
        isExporting = true
        defer { isExporting = false }
        let options = exportOptions
        do {
            // Decoded at the size it is exported at, as the previews are: the engine scales nothing.
            let source = try await sources.source(dimension: options.longSide ?? 0, settings: settings)
            let developed = try await renderer.render(source, settings: settings, quality: .full)
            try await Task.detached(priority: .userInitiated) {
                try ImageExporter.write(
                    developed, to: destination, options: options, originalURL: url,
                )
            }.value
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: - Several photos

    /// The folder beside the originals that takes the developed photos.
    static var developedFolderName: String {
        String(localized: "Developed", comment: "The name of the folder exported photos are written to, beside the originals")
    }

    /// Exports the photos the sheet was opened for: beside each original, or to a folder asked
    /// for now. When files of an earlier export are there, it stops and waits to be told what
    /// to do with them (`exportWaiting`).
    func exportPhotos() async {
        guard !photosToExport.isEmpty, !isExporting else { return }
        let destination: ExportDestination
        if exportsBesideOriginals {
            destination = .subfolder(Self.developedFolderName)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = String(localized: "Export")
            guard await panel.begin() == .OK, let folder = panel.url else { return }
            destination = .folder(folder)
        }
        await export(photosToExport, to: destination)
    }

    /// Goes on with the export that was waiting, doing with the files already there what the
    /// user chose.
    func resumeExport(_ policy: ExistingFilePolicy) async {
        guard let waiting = exportWaiting else { return }
        exportWaiting = nil
        await export(waiting.photos, to: waiting.destination, existing: policy)
    }

    /// Develops each photo with its own adjustments and writes it, one after the other. At the
    /// end only the photos that failed are named.
    ///
    /// - Parameter existing: what to do with the files of an earlier export. `nil` asks: when
    ///   there are any, nothing is exported and `exportWaiting` says how many.
    func export(_ photos: [URL], to destination: ExportDestination, existing: ExistingFilePolicy? = nil) async {
        guard let renderer, !isExporting, !photos.isEmpty else { return }
        // What is being changed on the photo on screen is part of what is exported.
        settingsDidChange()
        settleChange()
        let options = exportOptions
        let jobs = photos.map { photo in
            let settings = adjustments(of: photo).settings
            return ExportJob(photo: photo, settings: settings, fileName: exportFileName(for: photo, settings: settings))
        }
        if existing == nil {
            let there = BatchExporter.alreadyExported(jobs, at: destination).count
            if there > 0 {
                exportWaiting = WaitingExport(photos: photos, destination: destination, existing: there)
                return
            }
        }
        let policy = existing ?? .keepBoth
        isExporting = true
        batchExport = BatchExportProgress(position: 1, total: jobs.count, name: jobs[0].photo.lastPathComponent)
        let task = Task {
            await BatchExporter(renderer: renderer).export(jobs, to: destination, options: options, existing: policy) { [weak self] index, job in
                await self?.noteExport(of: job, at: index)
            }
        }
        exportTask = task
        let results = await task.value
        exportTask = nil
        batchExport = nil
        isExporting = false
        isExportPresented = false
        let failed = results.filter { !$0.succeeded }
        if !failed.isEmpty {
            alertMessage = Self.exportFailureMessage(for: failed.map(\.source.lastPathComponent))
        }
    }

    /// Stops the export of several photos after the photo being developed.
    func cancelExport() {
        exportTask?.cancel()
    }

    private func noteExport(of job: ExportJob, at index: Int) {
        batchExport?.position = index + 1
        batchExport?.name = job.photo.lastPathComponent
    }

    /// The name of an exported file: the photo's name and the film it was developed with.
    private func exportFileName(for photo: URL, settings: DevelopSettings) -> String {
        let film = films.first { $0.id == settings.filmID }?.displayName ?? settings.filmID
        return Self.exportFileName(source: photo, film: film, format: exportOptions.format)
    }

    /// How many names of failed photos the message lists before it counts the rest.
    private nonisolated static let listedFailures = 8

    /// What to say when photos could not be exported: how many, and which.
    nonisolated static func exportFailureMessage(for names: [String]) -> String {
        var lines = [String(localized: "\(names.count) photos could not be exported.")]
        lines += names.prefix(listedFailures)
        if names.count > listedFailures {
            lines.append(String(localized: "And \(names.count - listedFailures) more."))
        }
        return lines.joined(separator: "\n")
    }
}
