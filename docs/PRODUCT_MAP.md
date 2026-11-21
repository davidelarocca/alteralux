# Product map

What the user works with, where each thing lives, and how to get from one thing to another.
The code is the source of truth: every row points to a file. Updated in the same change as the code.
Built and refreshed with `/swift-harness:product-map`. Read this before showing an entity in a new place
or adding something the user creates or organizes.

## Rules

- **Every appearance leads to its destination.** Wherever an entity is shown (row, tile, header, inspector,
  menu, search result, mini player, notification), the user can open its destination from there: click,
  double-click, context menu or keyboard.
- **Related entities are reachable.** If a row shows a related entity (its container, owner, author,
  category), that name opens the related entity's destination. Text that looks like a link is a link.
- **Same entity, same actions.** An entity offers the actions in its action set wherever it appears, through
  the shared menu or command. Leaving one out is a decision, written in "Exceptions".
- **What the user creates, the user can manage.** Collections the user makes or organizes support create,
  rename, reorder, delete and undo, or the table says why not.

## Entities

| Entity | Model | Destination (full page) | Opened by |
|---|---|---|---|
| | `File.swift:line` | `DetailView` (`File.swift:line`) or none | the navigation call, e.g. `router.open(.entity(id))` |
| Recipe | `apple/AlteraluxKit/Sources/AlteraluxKit/Recipe.swift` | the recipes and workflows window (`RecipesWindow`, `RecipesWindow.swift`), the recipe chosen in its list | Recipes and Workflows… in the Recipe menu, or the Window menu; the window shows the first recipe until another is chosen |
| Workflow | `apple/AlteraluxKit/Sources/AlteraluxKit/Workflow.swift` | its recipe's page in `RecipesWindow`, where it is edited in a sheet (`WorkflowEditor`) | Edit… beside it in the recipe's page |
| Photo | a file of a folder of the library (`apple/AlteraluxKit/Sources/AlteraluxUI/Model/LibraryModel.swift`) | the develop screen (`DevelopScreen`, `MainScreen.swift`) | `AppModel.develop(_:)`: a double-click, Return, or Develop in its menu |

## Relations

| From | To | Kind (belongs to, author, category, ...) | Shown as link where |
|---|---|---|---|
| Workflow | Recipe | develops photos with it, named by id: a renamed recipe carries to it, a deleted one deletes it | listed under its recipe in `RecipesWindow`; named as text in the sheet that runs it (see Exceptions) |

## Appearances

One row per place an entity is displayed. ✓ = offered, — = missing (a gap), n/a = does not apply.

| Entity | Where (`File.swift:line`) | Opens destination | Related entities reachable | Action set |
|---|---|---|---|---|
| Recipe | The toolbar's Recipe menu while developing (`RecipeMenu.swift`, from `MainScreen.swift`) | n/a | n/a (its film and paper are shown as text) | ✓ |
| Recipe | The Recipe list of the library's selection bar (`LibrarySelectionBar.swift`) | n/a | n/a | Give only: see Exceptions |
| Recipe | The Recipe submenu of a photo's menu in the library (`PhotoMenus.swift`) | n/a | n/a | Give only: see Exceptions |
| Recipe | The list of `RecipesWindow` (`RecipesWindow.swift`) | ✓ a click shows its page | ✓ its workflows are on its page | ✓ Rename and Delete in its page and its context menu; Adapt in its page; Give and Save as New from the Recipe menu, see Exceptions |
| Workflow | A recipe's page in `RecipesWindow` (`RecipeDetail`) | n/a, it is the destination | ✓ its recipe is the page | ✓ Edit, Delete; New Workflow… |
| Workflow | The Workflow list of the library's selection bar (`LibrarySelectionBar.swift`) | n/a | n/a | Develop only: see Exceptions |
| Workflow | The Develop with Workflow submenu of a photo's menu in the library (`PhotoMenus.swift`) | n/a | n/a | Develop only: see Exceptions |
| Workflow | The export sheet's form for a workflow (`WorkflowRunForm.swift`) | n/a | its recipe named as text: see Exceptions | Develop only: see Exceptions |
| Workflow | The same form, for photos sent from the Finder's "Develop with alteralux…" (`AppModel+HandedOver.swift`); with no workflow yet, an alert leads to `RecipesWindow` (`MainScreen.swift`) | n/a | its recipe named as text: see Exceptions | Develop only: see Exceptions |
| Workflow | The Shortcuts action "Develop Photos" (`apple/Alteralux/Shortcuts/DevelopPhotosIntent.swift`), by name with what it writes | n/a, outside the app | n/a | Develop only: see Exceptions |
| Photo | A tile of the library's grid (`LibraryGrid.swift`) | ✓ double-click, Return, Develop in its menu | ✓ its folder is the one on screen; Show in Finder | ✓ the bar of the selection and the tile's menu |
| Photo | The photo being developed (`PhotoStage`, from `MainScreen.swift`) | n/a, it is the destination | ✓ Show in Finder; the way back to the library in the toolbar and Escape | ✓ the photo's menu, the toolbar and the menus |

## Action sets

| Entity | Actions | Shared entry point |
|---|---|---|
| | Open, Rename, Delete, ... | the shared menu or command type, with its file |
| Recipe | Give (to the photo on screen or to the selection), Save as New, Rename, Adapt to each photo (on or off), Delete (with its workflows, named first) | `RecipeMenu` (`apple/AlteraluxKit/Sources/AlteraluxUI/Views/RecipeMenu.swift`): give and save from the menu; rename, adapt and delete in `RecipesWindow` (`RecipesWindow.swift`), opened with Recipes and Workflows… |
| Workflow | New (for a recipe), Edit (name, format, size, destination), Delete, Develop the selected photos with it | `RecipeDetail` (`RecipesWindow.swift`) and `WorkflowEditor`; developing from the library's selection bar and a photo's menu, through `AppModel.presentWorkflowRun(_:)` |
| Photo | Develop, Show in Finder, Open With, give a Recipe, Export, Develop with Workflow, Share, Move to, Copy to, Duplicate, Rename (one photo), Tags, Copy, Paste and Reset Adjustments, Rotate Left and Right, Discard or Take Back, Move to Trash; while developing, Crop and Straighten. The bar of the selection has Recipe, Export, Workflow, Move to, Copy to, Tag and Discard; the tile's menu has them all, with the number of photos in their titles when they act on several | `LibrarySelectionBar` and `LibraryPhotoMenu` (`apple/AlteraluxKit/Sources/AlteraluxUI/Views/PhotoMenus.swift`) in the library, `DevelopPhotoMenu` while developing |

## User-managed collections

| Collection | Create | Rename | Reorder | Delete | Undo |
|---|---|---|---|---|---|
| Recipes | ✓ Save as New Recipe… | ✓ | — see Exceptions | ✓ after a confirmation | — see Exceptions |
| Workflows | ✓ New Workflow… in a recipe's page | ✓ in Edit… | — see Exceptions | ✓ after a confirmation | — see Exceptions |

## Exceptions

Deliberate departures from the rules, so they are not reported again.

| Where | Rule not applied | Why |
|---|---|---|
| Recipe, in the library's selection bar | Save as New, Rename, Delete | The bar gives a recipe to the selected photos; recipes are made and managed from the toolbar's Recipe menu while developing, where there is a look on screen |
| Recipes | Reorder | They are listed by name, like the films: an order of one's own waits for people to have many |
| Recipe, in `RecipesWindow` | Give, Save as New | Giving and saving need a photo: they are in the Recipe menu, where the photo or the selection is |
| Workflow, in the library's selection bar, a photo's menu and the sheet that runs it | Edit, Delete, opening its page | These lists develop the selected photos; workflows are made and changed in `RecipesWindow`, which the bar's empty list names |
| Workflow, in the Shortcuts action | Edit, Delete, opening its page | Shortcuts only chooses one, kept by id; workflows are made and changed in the app |
| Workflows | Reorder, Undo | Listed by name under their recipe, like the recipes; deleting asks first |
| Recipes | Undo of create, rename and delete | The window's undo is the history of the photos' adjustments; deleting asks first, and a recipe deleted by mistake is saved again from any photo that has its look |

## Known gaps

Found and not fixed yet, most important first.

| Gap | Evidence | Priority |
|---|---|---|
