import AlteraluxKit
import AppKit
import Foundation

// Workflows: a recipe and what to do with it, kept by the app beside the recipes. A workflow
// names its recipe by id, so a renamed recipe carries to it; deleting a recipe deletes its
// workflows, after the recipe window names them. Developing photos with a workflow only writes
// files: the photos keep their own adjustments.

extension AppModel {
    // MARK: - Keeping workflows

    /// Reads the workflows again from where they are kept.
    func loadWorkflows() async {
        workflows = await workflowStore.all()
    }

    /// The workflows that develop photos with `recipe`, by name.
    func workflows(using recipe: Recipe) -> [Workflow] {
        workflows.filter { $0.recipeID == recipe.id }
    }

    /// The recipe a workflow develops photos with, if it is still there.
    func recipe(of workflow: Workflow) -> Recipe? {
        recipes.first { $0.id == workflow.recipeID }
    }

    /// A new workflow for `recipe`, not kept yet: files the size of the original, in the
    /// folder exports go to beside the originals.
    func newWorkflow(for recipe: Recipe) -> Workflow {
        Workflow(
            name: recipe.name, recipeID: recipe.id,
            destination: .besideOriginals(folderName: Self.developedFolderName),
        )
    }

    /// Keeps a workflow, new or changed. Its name and the name of a folder beside the
    /// originals are trimmed; a blank one is not kept.
    func save(_ workflow: Workflow) async {
        var workflow = workflow
        workflow.name = workflow.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .besideOriginals(folderName) = workflow.destination {
            workflow.destination = .besideOriginals(folderName: folderName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard Self.canSave(workflow) else { return }
        do {
            try await workflowStore.save(workflow)
        } catch {
            alertMessage = String(localized: "The workflow “\(workflow.name)” could not be saved.")
        }
        await loadWorkflows()
    }

    /// Whether a workflow can be kept as it is: it has a name, and a folder to write to.
    static func canSave(_ workflow: Workflow) -> Bool {
        guard isRecipeName(workflow.name) else { return false }
        if case let .besideOriginals(folderName) = workflow.destination {
            return isFolderName(folderName)
        }
        return true
    }

    /// Whether `name` can name a folder beside the originals: not blank, no slash or colon,
    /// and not a hidden folder.
    static func isFolderName(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
    }

    /// Deletes a workflow. The files it wrote stay where they are.
    func delete(_ workflow: Workflow) async {
        do {
            try await workflowStore.delete(workflow.id)
        } catch {
            alertMessage = String(localized: "The workflow “\(workflow.name)” could not be deleted.")
        }
        await loadWorkflows()
    }

    // MARK: - Developing photos with a workflow

    /// Whether the selected photos of the library can be developed with a workflow.
    var canDevelopWithWorkflow: Bool {
        showsLibrary && canGiveLookToSelection && renderer != nil && !isExporting && !workflows.isEmpty
    }

    /// Shows the export sheet for the selected photos of the library, to develop them with a
    /// workflow: `workflow`, or the one chosen last time.
    func presentWorkflowRun(_ workflow: Workflow? = nil) {
        guard canDevelopWithWorkflow else { return }
        photosToExport = selectedPhotos
        let last = workflows.first { $0.id == exportWorkflow }
        exportWorkflow = (workflow ?? last ?? workflows.first)?.id
        exportsWithWorkflow = true
        isExportPresented = true
    }

    /// The workflow chosen in the export sheet, if it is still there.
    var chosenWorkflow: Workflow? {
        workflows.first { $0.id == exportWorkflow }
    }

    /// Develops the photos the sheet was opened for with the workflow chosen in it.
    func developWithWorkflow() async {
        guard !photosToExport.isEmpty, let workflow = chosenWorkflow, let recipe = recipe(of: workflow) else { return }
        let destination: ExportDestination
        switch workflow.destination {
        case let .besideOriginals(folderName):
            destination = .subfolder(folderName)
        case let .folder(bookmark):
            guard let folder = bookmark.resolve(), Self.isFolder(folder) else {
                alertMessage = String(
                    localized: "The folder “\(bookmark.name)” of the workflow “\(workflow.name)” cannot be found.",
                )
                return
            }
            destination = .folder(folder)
        }
        await export(photosToExport, to: destination, options: workflow.options, recipe: recipe)
    }

    /// Whether there is a folder at `url`. A folder that was taken away is not made again.
    private static func isFolder(_ url: URL) -> Bool {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Describing a workflow

    /// What a workflow writes, in a line: "JPEG · 2048 px · in “Developed” beside the originals".
    func summary(of workflow: Workflow) -> String {
        let format = switch workflow.options.format {
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .png: "PNG"
        }
        let size = workflow.options.longSide.map { String(localized: "\($0) px") }
            ?? String(localized: "Original size")
        let place = switch workflow.destination {
        case let .besideOriginals(folderName): String(localized: "in “\(folderName)” beside the originals")
        case let .folder(bookmark): String(localized: "in “\(bookmark.name)”")
        }
        return [format, size, place].joined(separator: " · ")
    }
}

extension AppModel {
    /// Asks for the folder a workflow writes to, and remembers it so the app can write there
    /// again without asking. `nil` when none is chosen.
    func chooseWorkflowFolder() async -> FolderBookmark? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        guard await panel.begin() == .OK, let folder = panel.url else { return nil }
        do {
            return try FolderBookmark(for: folder)
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }
}
