import AlteraluxKit
import AppKit
import Foundation
import UniformTypeIdentifiers

// Photos handed over from outside the app to develop with a workflow: from the Finder's
// "Develop with alteralux…" (a Services entry) and from the Shortcuts action "Develop Photos".
// They are developed as the library's selected photos are, and are not added to the library or
// to the strip.

extension AppModel {
    // MARK: - From the Finder

    /// Shows the sheet that develops photos with a workflow, for photos handed over by the
    /// Finder. What is not a photo is left out.
    public func developWithWorkflow(handedOver urls: [URL]) {
        openMainWindow?()
        let photos = urls.filter(Self.isPhoto)
        guard !photos.isEmpty else {
            alertMessage = String(localized: "None of these files is a photo alteralux can develop.")
            return
        }
        guard !isExporting else {
            alertMessage = String(localized: "alteralux is already developing photos. Try again when it is done.")
            return
        }
        photosToExport = photos
        exportWorkflow = (workflows.first { $0.id == exportWorkflow } ?? workflows.first)?.id
        exportsWithWorkflow = true
        exportWaiting = nil
        isExportPresented = true
    }

    /// Whether `url` is a file of a kind the app develops.
    static func isPhoto(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return openableTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Folders to write into

    /// The folders that hold `photos` and that the app may not write into yet: outside the
    /// library's folders and the folders the user let it write into before. The sandbox lets
    /// the app read a photo handed over by the Finder, not write beside it.
    func foldersNeedingPermission(for photos: [URL]) async -> [URL] {
        let allowed = await library.roots.map(\.folder.url)
            + writableFolders.folders().filter(\.isAvailable).map(\.url)
        let holding = Set(photos.map { $0.deletingLastPathComponent().standardizedFileURL })
        return holding.filter { folder in !allowed.contains { Self.isInside(folder, $0) } }
            .sorted { $0.path < $1.path }
    }

    /// Whether `url` is `folder` or inside it.
    nonisolated static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return path.starts(with: base)
    }

    /// Asks the user, for each of `folders`, to let the app write into it: the system's open
    /// panel, on that folder. The folders allowed are remembered, so each is asked for once.
    /// Returns whether all of them were allowed.
    func askToWrite(into folders: [URL], folderName: String) async -> Bool {
        for folder in folders {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            let name = folder.lastPathComponent
            panel.message = String(
                localized: "To write “\(folderName)” beside the photos, alteralux needs your permission for the folder “\(name)”. It is asked only once.",
            )
            panel.prompt = String(localized: "Allow")
            guard await panel.begin() == .OK, let chosen = panel.url else { return false }
            guard Self.isInside(folder, chosen) else {
                alertMessage = String(
                    localized: "“\(chosen.lastPathComponent)” does not hold the photos. Choose the folder “\(name)”, or one that holds it.",
                )
                return false
            }
            do {
                try await writableFolders.add(chosen)
            } catch {
                alertMessage = error.localizedDescription
                return false
            }
        }
        return true
    }

    // MARK: - From Shortcuts

    /// The workflows as the Shortcuts action offers them, by name.
    public func workflowChoices() async -> [WorkflowChoice] {
        await loadRecipes()
        await loadWorkflows()
        return workflows.map { WorkflowChoice(id: $0.id, name: $0.name, summary: summary(of: $0)) }
    }

    /// Develops `photos` with a workflow for the Shortcuts action, and gives back the files
    /// written. A workflow that writes into a folder of its own writes there; one that writes
    /// beside the originals writes into `scratch`, because what Shortcuts hands over is often a
    /// copy of the photo, and the shortcut takes the files on from there. A file already there
    /// is kept, and the new one takes the next free name.
    public func developForShortcut(_ photos: [URL], workflow id: UUID, scratch: URL) async throws -> [DevelopedFile] {
        await start()
        await loadRecipes()
        await loadWorkflows()
        guard let renderer else { throw HandedOverError.engineUnavailable }
        guard let workflow = workflows.first(where: { $0.id == id }) else { throw HandedOverError.workflowMissing }
        guard let recipe = recipe(of: workflow) else { throw HandedOverError.recipeMissing(workflow.name) }
        let folder: URL
        switch workflow.destination {
        case .besideOriginals:
            folder = scratch
        case let .folder(bookmark):
            guard let chosen = bookmark.resolve() else {
                throw HandedOverError.folderMissing(bookmark.name, workflow: workflow.name)
            }
            folder = chosen
        }
        let isScoped = folder.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jobs = exportJobs(photos.filter(Self.isPhoto), options: workflow.options, recipe: recipe)
        guard !jobs.isEmpty else { throw HandedOverError.noPhotos }
        let results = await BatchExporter(renderer: renderer, lenses: lenses)
            .export(jobs, to: .folder(folder), options: workflow.options, existing: .keepBoth)
        // Read while the folder can be reached: Shortcuts takes the files as data.
        let type = workflow.options.format.contentType
        let files = results.compactMap { result in
            result.destination.flatMap { url in
                (try? Data(contentsOf: url)).map { DevelopedFile(name: url.lastPathComponent, data: $0, type: type) }
            }
        }
        guard !files.isEmpty else {
            throw HandedOverError.nothingDeveloped(Self.exportFailureMessage(for: results.map(\.source.lastPathComponent)))
        }
        return files
    }
}

/// A workflow as the Shortcuts action offers it.
public struct WorkflowChoice: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    /// What it writes, in a line: "JPEG · 2048 px · in “Developed” beside the originals".
    public let summary: String
}

/// A file a workflow wrote, as the Shortcuts action gives it back.
public struct DevelopedFile: Sendable {
    public let name: String
    public let data: Data
    public let type: UTType
}

/// Why photos handed over to the app could not be developed.
public enum HandedOverError: LocalizedError, Equatable {
    case engineUnavailable
    case workflowMissing
    case recipeMissing(String)
    case folderMissing(String, workflow: String)
    case noPhotos
    case nothingDeveloped(String)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            String(localized: "alteralux could not start its film engine.")
        case .workflowMissing:
            String(localized: "The workflow is no longer in alteralux.")
        case let .recipeMissing(workflow):
            String(localized: "The recipe of the workflow “\(workflow)” is no longer in alteralux.")
        case let .folderMissing(folder, workflow):
            String(localized: "The folder “\(folder)” of the workflow “\(workflow)” cannot be found.")
        case .noPhotos:
            String(localized: "None of these files is a photo alteralux can develop.")
        case let .nothingDeveloped(message):
            message
        }
    }
}
