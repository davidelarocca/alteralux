# Layout contract

How each main screen holds up as its window or pane is resized. Read it before changing the layout of a
screen listed here, and update it in the same change.

Sizes are in points, `<width>x<height>`, or `<width>` alone when the height does not matter.

- The end-of-turn check (swift-harness) keeps the table true: each View exists in its File, and tests
  measure the View and the Window.
- The tests do the measuring, with `LayoutContract.check("<View or Window>") { ... }`:
  - **View**, the screen's content, is proposed each size of its row: Min, just below and at Compact below,
    Default, Max. It fails when it needs more room than that: content clipped or pushed out of the window.
  - **Window**, the view the window shows (the content with the window's `.frame(minWidth:minHeight:)`), must
    declare Min as its minimum: not less, or the window shrinks to sizes the screen was not designed for; not
    more, or it never reaches Min. With a Max, it must not grow past it.
  - Measure the content without the window's frame: a minimum or fixed frame around a view hides content
    wider than the frame.
- Not measured: truncated text, overlapping content, and where popovers and secondary windows open. Those are
  checked in review, against the rows below.

## Screens

| Screen | View | File | Window | Min | Default | Max | Compact below | Compact behavior |
|---|---|---|---|---|---|---|---|---|
| Main window | `MainWindow` | apple/AlteraluxKit/Sources/AlteraluxUI/Views/MainScreen.swift | `MainWindow` | 900x600 | 1280x820 | - | - | - |
| Library, the folders | `LibrarySidebar` | apple/AlteraluxKit/Sources/AlteraluxUI/Views/LibraryScreen.swift | | 180x548 | 220x768 | 320 | - | - |
| Library, the photos | `LibraryGrid` | apple/AlteraluxKit/Sources/AlteraluxUI/Views/LibraryGrid.swift | | 580x548 | 1060x768 | - | - | - |

- **View**: the SwiftUI type of the screen's content. **File**: where it is declared, from the repository root.
  A split view (`NavigationSplitView`, `HSplitView`) takes any width, so its content cannot be measured: name
  its window type as View and Window, and give each page of the detail column and the sidebar a row of its own,
  with Min the width its column gets at the window's Min.
- **Window**: for a screen that fills a window, the type the window shows, which declares the window's
  minimum size. Empty for a pane (a sidebar, an inspector, a detail column), which is measured as View only.
- **Max**: a size, or `-` for none. **Compact below**: a width under which the screen switches to a compact
  layout, or `-`. **Compact behavior**: what changes below it.

## Presented UI

Popovers, sheets, menus, tooltips and secondary windows opened from these screens. At the screen's Min size
they must open inside the window, or on screen for a separate window.

| Element | Opened from | Kind | Size | At the minimum size |
|---|---|---|---|---|
| `ExportSheet` | Main window, Export; Library, Export… of the selection's bar | sheet | 420 wide | fits inside the 900 pt window |
| `RecipeMenu` | Main window, the toolbar's Recipe button; Library, Recipe of the selection's bar | system menu | system | system |
| Name of a recipe | `RecipeMenu`, Save as New Recipe… and Rename | system alert with a text field | system | centered in the window |
| Deleting a recipe | `RecipeMenu`, Delete | system confirmation dialog | system | centered in the window |
| Folder panel | `ExportSheet`, Export with "Another folder…" | system open panel | system | separate window |
| `FilmPicker` | Main window, the film heading of the inspector | popover | 300x420 | opens under the heading, inside the window |
| Open panel | Main window, Open | system file importer | system | system |
| Save panel | `ExportSheet`, Export | system save panel | system | separate window |
| About panel | App menu | system About panel | system | separate window |

## Exceptions

Deliberate departures from the rules above, with the reason.

- The library is a split view inside the main window: the window's own row checks the window's sizes, and
  its two columns have a row each. Their Min is what each gets at the window's Min (900x600 less the
  toolbar): the list of folders at its narrowest, and the photos beside the list at its widest.

- With photos selected the library's grid has `LibrarySelectionBar` under it. It never cuts a title:
  where the column is too narrow for every action side by side, clearing the selection becomes an
  icon, then moving, copying and tagging go into one menu. A layout test measures the grid with a
  selection.

- The main window holds an inspector, which behaves like a split view: its row names the window type as
  View and Window, so the row checks the window's sizes.
- The panes of the main window have no rows of their own yet. `PhotoStage` and `FilmstripView` scroll or
  scale their content and `InspectorView` is a scrolling `Form`: each takes any width, so
  `LayoutContract.check` cannot measure them. What they hold is checked through the shared components:
  `ParameterSlider` has snapshots at 280 pt, the inspector's minimum width, with a long title too. The
  screenshots of the main window at Min and Default show the panes together, for review.
- The zoom controls under the photo have a fixed width (about 400 pt). At the window's Min the photo
  pane is 580 pt wide with the inspector at its ideal width, so they fit.
