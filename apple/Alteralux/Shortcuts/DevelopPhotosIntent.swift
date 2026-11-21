import AlteraluxUI
import AppIntents
import Foundation

/// "Develop Photos" in Shortcuts: photos developed with a workflow of the app, and the files it
/// writes given back to the shortcut. It runs in the app, which starts without coming to the
/// front when it is not running.
struct DevelopPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "Develop Photos"
    static let description = IntentDescription(
        "Develops photos with a workflow of alteralux and gives back the files it writes. A workflow with a folder of its own also leaves them there.",
    )

    @Parameter(title: "Photos", supportedContentTypes: [.image])
    var photos: [IntentFile]

    @Parameter(title: "Workflow")
    var workflow: WorkflowEntity

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Develop \(\.$photos) with \(\.$workflow)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let manager = FileManager.default
        // The copies of this run, removed at the end: the files go back to the shortcut as data.
        let run = manager.temporaryDirectory.appending(path: "Shortcuts/\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: run) }
        let copies = run.appending(path: "Photos", directoryHint: .isDirectory)
        try manager.createDirectory(at: copies, withIntermediateDirectories: true)

        // A photo that comes as a file on disk is developed there, with its own adjustments;
        // one that comes as data is developed from a copy.
        var reached: [URL] = []
        defer {
            for url in reached {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var urls: [URL] = []
        for photo in photos {
            if let url = photo.fileURL {
                if url.startAccessingSecurityScopedResource() {
                    reached.append(url)
                }
                if manager.isReadableFile(atPath: url.path) {
                    urls.append(url)
                    continue
                }
            }
            let copy = copies.appending(path: photo.filename.isEmpty ? UUID().uuidString : photo.filename)
            try photo.data.write(to: copy)
            urls.append(copy)
        }

        let files = try await model.developForShortcut(
            urls, workflow: workflow.id, scratch: run.appending(path: "Developed", directoryHint: .isDirectory),
        )
        return .result(value: files.map { IntentFile(data: $0.data, filename: $0.name, type: $0.type) })
    }
}

/// A workflow of the app as Shortcuts shows it: chosen by name, kept by id, so a workflow
/// renamed in the app stays chosen in the shortcut.
struct WorkflowEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workflow"
    static let defaultQuery = WorkflowQuery()

    let id: UUID
    let name: String
    /// What it writes: "JPEG · 2048 px · in “Developed” beside the originals".
    let summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }

    init(_ choice: WorkflowChoice) {
        id = choice.id
        name = choice.name
        summary = choice.summary
    }
}

/// The workflows the app keeps, read when Shortcuts asks.
struct WorkflowQuery: EntityQuery {
    @Dependency private var model: AppModel

    @MainActor
    func entities(for identifiers: [WorkflowEntity.ID]) async throws -> [WorkflowEntity] {
        await model.workflowChoices().filter { identifiers.contains($0.id) }.map(WorkflowEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [WorkflowEntity] {
        await model.workflowChoices().map(WorkflowEntity.init)
    }
}
