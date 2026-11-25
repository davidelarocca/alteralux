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
| Recipe | `apple/AlteraluxKit/Sources/AlteraluxKit/Recipe.swift`, with the files it writes (`RecipeFiles.swift`) | the recipes window (`RecipesWindow`, `RecipesWindow.swift`), the recipe chosen in its list | Manage Recipes… in the Recipe menu, or the Window menu; the window shows the first recipe until another is chosen |
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
| Recipe | The list of `RecipesWindow` (`RecipesWindow.swift`) | ✓ a click shows its page | n/a (its film and paper are shown as text) | ✓ Edit, Duplicate and Delete in its page and its context menu; Give, Develop with and Save as New where the photos are, see Exceptions |
| Recipe | The Develop with… list of the library's selection bar (`LibrarySelectionBar.swift`), each with the files it writes | n/a | n/a | Develop with only: see Exceptions |
| Recipe | The Develop with Recipe submenu of a photo's menu in the library (`PhotoMenus.swift`) | n/a | n/a | Develop with only: see Exceptions |
| Recipe | The export sheet's form for developing with a recipe (`RecipeRunForm.swift`) | n/a | n/a | Develop with only: see Exceptions |
| Recipe | The Finder's panel for photos sent from "Develop with alteralux…" (`FinderPanel.swift`, `AppModel+HandedOver.swift`): which recipe, and only the settings it leaves open | n/a | n/a | Develop with only: see Exceptions |
| Recipe | The Shortcuts action "Develop Photos" (`apple/Alteralux/Shortcuts/DevelopPhotosIntent.swift`), by name with what it writes | n/a, outside the app | n/a | Develop with only: see Exceptions |
| Photo | A tile of the library's grid (`LibraryGrid.swift`) | ✓ double-click, Return, Develop in its menu | ✓ its folder is the one on screen; Show in Finder | ✓ the bar of the selection and the tile's menu |
| Photo | The photo being developed (`PhotoStage`, from `MainScreen.swift`) | n/a, it is the destination | ✓ Show in Finder; the way back to the library in the toolbar and Escape | ✓ the photo's menu, the toolbar and the menus |
| Photo | A thumbnail of the strip under the photo being developed (`FilmstripView.swift`), with the grid's marks and its colored tags as dots | ✓ a click shows it | ✓ Show in Finder; the way back to its folder in the toolbar | Its menu (`StripPhotoMenu`) acts on the thumbnail's photo, the one on screen stays: Show in Finder, give a Recipe, Export, Share, Tags, Copy, Paste and Reset Adjustments, Discard, which also takes the photo out of the strip as it takes it out of the grid (Take Back for a photo opened from the discarded ones; Remove from Strip in its place for a photo that is not of the folder on screen, which cannot be discarded), and Move to Trash. The View menu's command for the photo on screen is the same Discard. The rest: see Exceptions |

## Action sets

| Entity | Actions | Shared entry point |
|---|---|---|
| | Open, Rename, Delete, ... | the shared menu or command type, with its file |
| Recipe | Give (to the photo on screen or to the selection: their adjustments change), Develop with (the selected photos, or the photos sent from the Finder: its files are written and the photos keep their adjustments), Save as New (the name, and the files it writes), Edit (name, format, size, file names, destination, each of the last four can be asked each time), Duplicate, Delete | `RecipeMenu` (`apple/AlteraluxKit/Sources/AlteraluxUI/Views/RecipeMenu.swift`): give and save from the menu; edit, duplicate and delete in `RecipesWindow` (`RecipesWindow.swift`), opened with Manage Recipes…, through `RecipeEditor`; developing from the library's selection bar and a photo's menu, through `AppModel.presentRecipeRun(_:)` |
| Photo | Develop, Show in Finder, Open With, give a Recipe, Export, Develop with Recipe, Share, Move to, Copy to, Duplicate, Rename (one photo), Tags, Copy, Paste and Reset Adjustments, Rotate Left and Right, Discard or Take Back, Move to Trash; while developing, Crop and Straighten. The bar of the selection has Recipe, Export, Develop with, Move to, Copy to, Tag and Discard; the tile's menu has them all, with the number of photos in their titles when they act on several | `LibrarySelectionBar` and `LibraryPhotoMenu` (`apple/AlteraluxKit/Sources/AlteraluxUI/Views/PhotoMenus.swift`) in the library, `DevelopPhotoMenu` while developing and `StripPhotoMenu` on a thumbnail of the strip, in the same file |

## User-managed collections

| Collection | Create | Rename | Reorder | Delete | Undo |
|---|---|---|---|---|---|
| Recipes | ✓ Save as New Recipe…, Duplicate… | ✓ in Edit… | — see Exceptions | ✓ after a confirmation | — see Exceptions |

## Exceptions

Deliberate departures from the rules, so they are not reported again.

| Where | Rule not applied | Why |
|---|---|---|
| Recipe, in the Recipe list of the library's selection bar and of a photo's menu | Save as New, Edit, Duplicate, Delete | The list gives a recipe to the selected photos; recipes are made from the toolbar's Recipe menu while developing, where there is a look on screen, and managed in `RecipesWindow` |
| Photo, in the strip's menu | Open With, Develop with Recipe, Move to, Copy to, Duplicate, Rename, Rotate Left and Right | The strip is where a series is developed: its menu has what is done to a photo meanwhile (decided with the user on 2026-11-25). What arranges the files, turning, and writing files with a recipe stay in the library, one step away in the toolbar; the frame of the photo on screen is turned in Crop and Straighten |
| Recipes | Reorder | They are listed by name, like the films: an order of one's own waits for people to have many |
| Recipe, in `RecipesWindow` | Give, Develop with, Save as New | They need photos: they are in the Recipe menu and in the library, where the photo or the selection is |
| Recipe, in the Develop with… list of the library's selection bar, a photo's menu, the sheet and the Finder's panel that develop with it | Give, Edit, Duplicate, Delete, opening its page | These develop photos with a recipe; what it leaves open is asked there, and the rest is changed in `RecipesWindow` |
| Recipe, in the toolbar's Recipe menu while developing | Develop with | The photo on screen is exported with its own adjustments (Export…); developing with a recipe is for photos that keep theirs, from the library and the Finder |
| Recipe, in the Shortcuts action | everything but Develop with | Shortcuts only chooses one, kept by id; recipes are made and changed in the app |
| Recipes | Undo of create, rename and delete | The window's undo is the history of the photos' adjustments; deleting asks first, and a recipe deleted by mistake is saved again from any photo that has its look |

## Known gaps

Found and not fixed yet, most important first.

| Gap | Evidence | Priority |
|---|---|---|
