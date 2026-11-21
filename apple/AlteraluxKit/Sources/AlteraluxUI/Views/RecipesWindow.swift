import AlteraluxKit
import DesignSystem
import SwiftUI

/// The window of recipes and workflows: the recipes on the left, and on the right the one chosen,
/// with whether it adapts to each photo and the workflows that use it. Renaming and deleting a
/// recipe are here; a recipe is made from the look on screen, with the Recipe menu.
public struct RecipesWindow: View {
    /// The window's identifier, to open it.
    public static let id = "recipes"
    /// The smallest size the window can be resized to, in points.
    public static let minimumSize = CGSize(width: 640, height: 480)
    /// The size of a new window, in points.
    public static let defaultSize = CGSize(width: 780, height: 640)

    public init() {}

    public var body: some View {
        RecipesScreen()
            .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

/// The recipes and, for the one chosen, its workflows.
struct RecipesScreen: View {
    @Environment(AppModel.self) private var model

    @State private var selection: Recipe.ID?
    @State private var question: RecipeQuestion?
    @State private var name = ""

    var body: some View {
        NavigationSplitView {
            List(model.recipes, selection: $selection) { recipe in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: recipe.name)
                    Text(verbatim: model.materials(of: recipe.look))
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contextMenu {
                    Button("Rename…") { ask(.rename, recipe) }
                    Button("Delete…", role: .destructive) { ask(.delete, recipe) }
                }
            }
            .navigationSplitViewColumnWidth(
                min: SidebarWidth.minimum, ideal: SidebarWidth.ideal, max: SidebarWidth.maximum,
            )
        } detail: {
            if let recipe = chosen {
                RecipeDetail(recipe: recipe, rename: { ask(.rename, recipe) }, delete: { ask(.delete, recipe) })
            } else {
                ContentUnavailableView(
                    "No Recipes",
                    systemImage: "camera.filters",
                    description: Text("Save the look of a photo as a recipe with the Recipe menu, while developing it."),
                )
            }
        }
        .navigationTitle("Recipes and Workflows")
        .navigationSubtitle(chosen.map { Text(verbatim: $0.name) } ?? Text(verbatim: ""))
        .onChange(of: model.recipes, initial: true) {
            if chosen == nil {
                selection = model.recipes.first?.id
            }
        }
        .alert("Rename Recipe", isPresented: isAsking(.rename)) {
            TextField("Name", text: $name)
            Button("Rename") { answer { recipe in await model.rename(recipe, to: name) } }
                .disabled(!AppModel.isRecipeName(name))
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete the recipe “\(question?.recipe?.name ?? "")”?", isPresented: isAsking(.delete),
        ) {
            Button("Delete", role: .destructive) { answer { recipe in await model.delete(recipe) } }
        } message: {
            Text(deletionMessage)
        }
    }

    /// The recipe chosen in the list, if it is still there.
    private var chosen: Recipe? {
        model.recipes.first { $0.id == selection }
    }

    /// What deleting the recipe asked about takes with it: its workflows, by name.
    private var deletionMessage: String {
        let workflows = question?.recipe.map { model.workflows(using: $0).map(\.name) } ?? []
        if workflows.isEmpty {
            return String(localized: "The photos that received it keep their adjustments.")
        }
        let names = workflows.map { "“\($0)”" }.formatted(.list(type: .and))
        return String(localized: "Its workflows are deleted too: \(names). The photos that received it keep their adjustments.")
    }

    private func ask(_ kind: RecipeQuestion.Kind, _ recipe: Recipe) {
        name = recipe.name
        question = RecipeQuestion(kind: kind, recipe: recipe)
    }

    private func isAsking(_ kind: RecipeQuestion.Kind) -> Binding<Bool> {
        Binding(
            get: { question?.kind == kind },
            set: {
                if !$0, question?.kind == kind {
                    question = nil
                }
            },
        )
    }

    /// Acts on the answer, with the recipe the question was about.
    private func answer(_ action: @escaping (Recipe) async -> Void) {
        guard let recipe = question?.recipe else { return }
        question = nil
        Task { await action(recipe) }
    }
}

/// One recipe: its film and paper, whether it adapts to each photo, and its workflows.
struct RecipeDetail: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe
    let rename: () -> Void
    let delete: () -> Void

    /// The workflow being made or changed in the editor.
    @State private var editing: WorkflowDraft?
    @State private var workflowToDelete: Workflow?

    var body: some View {
        Form {
            Section {
                LabeledContent("Film and paper") {
                    Text(verbatim: model.materials(of: recipe.look))
                }
                Toggle("Adapts to each photo", isOn: adapts)
                    .help("Each photo starts from its own exposure, and from an automatic white balance where the camera's is far off.")
            } footer: {
                note("A recipe is a look saved under a name: everything but the white balance.")
            }
            workflows
            Section {
                HStack(spacing: Spacing.s) {
                    Button("Rename Recipe…", action: rename)
                    Button("Delete Recipe…", role: .destructive, action: delete)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { draft in
            WorkflowEditor(draft: draft)
        }
        .confirmationDialog(
            "Delete the workflow “\(workflowToDelete?.name ?? "")”?", isPresented: isDeleting,
        ) {
            Button("Delete", role: .destructive) {
                guard let workflow = workflowToDelete else { return }
                workflowToDelete = nil
                Task { await model.delete(workflow) }
            }
        } message: {
            Text("The files it wrote stay where they are.")
        }
    }

    private var workflows: some View {
        Section {
            let workflows = model.workflows(using: recipe)
            if workflows.isEmpty {
                Text("No Workflows")
                    .foregroundStyle(.secondary)
            }
            ForEach(workflows) { workflow in
                LabeledContent {
                    HStack(spacing: Spacing.s) {
                        Button("Edit…") { editing = WorkflowDraft(workflow: workflow, isNew: false) }
                        Button("Delete…", role: .destructive) { workflowToDelete = workflow }
                    }
                    .fixedSize()
                } label: {
                    Text(verbatim: workflow.name)
                    Text(verbatim: model.summary(of: workflow))
                }
            }
            Button("New Workflow…") {
                editing = WorkflowDraft(workflow: model.newWorkflow(for: recipe), isNew: true)
            }
        } header: {
            Text("Workflows")
        } footer: {
            note("A workflow develops photos with this recipe and writes them as files. In the library, select photos and choose Develop with Workflow.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether the recipe adapts to each photo, saved as soon as it changes.
    private var adapts: Binding<Bool> {
        Binding(
            get: { recipe.adaptsToEachPhoto },
            set: { adapts in Task { await model.setAdapts(recipe, adapts) } },
        )
    }

    private var isDeleting: Binding<Bool> {
        Binding(
            get: { workflowToDelete != nil },
            set: {
                if !$0 {
                    workflowToDelete = nil
                }
            },
        )
    }
}
