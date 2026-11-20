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
| Recipe | `apple/AlteraluxKit/Sources/AlteraluxKit/Recipe.swift` | none: a recipe is a name and a look, it has no page of its own | n/a |
| Photo | a file of a folder of the library (`apple/AlteraluxKit/Sources/AlteraluxUI/Model/LibraryModel.swift`) | the develop screen (`DevelopScreen`, `MainScreen.swift`) | `AppModel.develop(_:)`: a double-click, Return, or Develop in its menu |

## Relations

| From | To | Kind (belongs to, author, category, ...) | Shown as link where |
|---|---|---|---|

## Appearances

One row per place an entity is displayed. ✓ = offered, — = missing (a gap), n/a = does not apply.

| Entity | Where (`File.swift:line`) | Opens destination | Related entities reachable | Action set |
|---|---|---|---|---|
| Recipe | The toolbar's Recipe menu while developing (`RecipeMenu.swift`, from `MainScreen.swift`) | n/a | n/a (its film and paper are shown as text) | ✓ |
| Recipe | The Recipe list of the library's selection bar (`LibrarySelectionBar.swift`) | n/a | n/a | Give only: see Exceptions |
| Recipe | The Recipe submenu of a photo's menu in the library (`PhotoMenus.swift`) | n/a | n/a | Give only: see Exceptions |
| Photo | A tile of the library's grid (`LibraryGrid.swift`) | ✓ double-click, Return, Develop in its menu | ✓ its folder is the one on screen; Show in Finder | ✓ the bar of the selection and the tile's menu |
| Photo | The photo being developed (`PhotoStage`, from `MainScreen.swift`) | n/a, it is the destination | ✓ Show in Finder; the way back to the library in the toolbar and Escape | ✓ the photo's menu, the toolbar and the menus |

## Action sets

| Entity | Actions | Shared entry point |
|---|---|---|
| | Open, Rename, Delete, ... | the shared menu or command type, with its file |
| Recipe | Give (to the photo on screen or to the selection), Save as New, Rename, Delete | `RecipeMenu` (`apple/AlteraluxKit/Sources/AlteraluxUI/Views/RecipeMenu.swift`) |
| Photo | Develop, Show in Finder, give a Recipe, Export, Move to, Copy to, Tag, Copy and Paste Adjustments, Discard or Take Back | `LibrarySelectionBar` and `LibraryPhotoMenu` (`apple/AlteraluxKit/Sources/AlteraluxUI/Views/PhotoMenus.swift`) in the library, `DevelopPhotoMenu` while developing |

## User-managed collections

| Collection | Create | Rename | Reorder | Delete | Undo |
|---|---|---|---|---|---|
| Recipes | ✓ Save as New Recipe… | ✓ | — see Exceptions | ✓ after a confirmation | — see Exceptions |

## Exceptions

Deliberate departures from the rules, so they are not reported again.

| Where | Rule not applied | Why |
|---|---|---|
| Recipe, in the library's selection bar | Save as New, Rename, Delete | The bar gives a recipe to the selected photos; recipes are made and managed from the toolbar's Recipe menu while developing, where there is a look on screen |
| Recipes | Reorder | They are listed by name, like the films: an order of one's own waits for people to have many |
| Photo, in its menu in the library | Tag | The tags of a photo are read from its file; the bar's list reads them when it opens, a menu would read them for every tile shown |
| Recipes | Undo of create, rename and delete | The window's undo is the history of the photos' adjustments; deleting asks first, and a recipe deleted by mistake is saved again from any photo that has its look |

## Known gaps

Found and not fixed yet, most important first.

| Gap | Evidence | Priority |
|---|---|---|
