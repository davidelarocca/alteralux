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

**A drop-down never leaves the window.** A menu, a pop-up button or a list that opens from a control
stays inside the window's edges, at every size of its row. A system `Menu` or `Picker(.menu)` opens
downward from its button's leading edge toward the trailing one: it is used only where there is room
that way, on the leading side of the toolbar or at the top of a pane. On the trailing side of the
toolbar a menu is a `WindowMenuButton`, the same system menu opened where it stays inside the window,
and it has no submenus, which would open past the trailing edge. A pop-up button in a form is a
`WindowPopUp`: the system opens its menu with the chosen option over the button, so it hangs past the
window's bottom or top edge when the button is near one; `WindowPopUp` moves it inside. A control in a
bar near the bottom edge uses `ChoiceListButton`, whose list opens above it inside the window. Every
new drop-down gets a row in the table below, and is
opened in the built app at the window's Min before the change is done. Context menus (a secondary
click) are the system's and open at the pointer: they are the one exception.

| Element | Opened from | Kind | Size | At the minimum size |
|---|---|---|---|---|
| `ExportSheet` | Main window, Export; Library, Export… of the selection's bar | sheet | 420 wide | fits inside the 900 pt window |
| Filter and Sort | Library, the trailing side of the toolbar | system menu, no submenus (`WindowMenuButton`) | system | under the button, moved toward the leading side to stay inside the window (measured at 900 pt) |
| `RecipeMenu` | Main window, the toolbar's Recipe button | system menu, no submenus (`WindowMenuButton`) | system | under the button, moved toward the leading side to stay inside the window |
| `RecipeManager` | `RecipeMenu`, Manage Recipes… | sheet (`FormSheet`) | 420 wide | fits inside the 900 pt window |
| Lists of the selection's bar | Library, Recipe, Move to…, Copy to… and Tag of the bar | popover above the button | 260 wide, up to 320 tall | opens upward, inside the window |
| Shape of the frame | Main window, the crop's controls under the photo | popover above the button (`ChoiceListButton`) | 260 wide, up to 320 tall | opens upward, inside the window |
| Name of a recipe | `RecipeMenu`, Save as New Recipe…; `RecipeManager`, Rename… | system alert with a text field | system | centered in the window |
| Deleting a recipe | `RecipeManager`, Delete… | system confirmation dialog | system | centered in the window |
| Files already exported | `ExportSheet`, Export when files of an earlier export are in the destination | system alert | system | centered in the window |
| Folder panel | `ExportSheet`, Export with "Another folder…" | system open panel | system | separate window |
| Paper, film format, development times | Main window, the inspector's pop-up buttons (`WindowPopUp`) | system pop-up menu | system | over the button as the system opens it; moved inside the window where it would pass the bottom or top edge (measured at 900 pt, the paper's menu with its last paper chosen) |
| `FilmPicker` | Main window, the film heading of the inspector | popover | 300 wide, 420 to 640 tall: the inspector's height less 130 | opens under the heading, inside the window |
| Open panel | Main window, Open | system file importer | system | system |
| Save panel | `ExportSheet`, Export | system save panel | system | separate window |
| About panel | App menu | system About panel | system | separate window |

## Exceptions

Deliberate departures from the rules above, with the reason.

- The library is a split view inside the main window: the window's own row checks the window's sizes, and
  its two columns have a row each. Their Min is what each gets at the window's Min (900x600 less the
  toolbar): the list of folders at its narrowest, and the photos beside the list at its widest.

- With photos selected the library's grid has `LibrarySelectionBar` floating over it, near its bottom
  edge. It never cuts a title: where the column is too narrow for every action side by side, moving,
  copying and tagging show their symbols alone. Its lists (`ChoiceListButton`: recipes, folders, tags)
  open above the bar, inside the window, at most 320 pt tall. A layout test measures the grid with a
  selection.
- The library's grid lays its photos in rows, each photo as wide as its own shape, and every row
  but the last reaches both edges of the grid, made up to half again taller or shorter to do so:
  the rows are computed for the width the grid has (`LibraryRows`), so no photo is cut or pushed out
  at any size of its row.

- The main window holds an inspector, which behaves like a split view: its row names the window type as
  View and Window, so the row checks the window's sizes. A photo opens with the inspector closed; the
  sizes are those with it open, the narrowest the photo gets.
- The panes of the main window have no rows of their own yet. `PhotoStage` and `FilmstripView` scroll or
  scale their content and `InspectorView` is a scrolling `Form`: each takes any width, so
  `LayoutContract.check` cannot measure them. What they hold is checked through the shared components:
  `ParameterSlider` has snapshots at 280 pt, the inspector's minimum width, with a long title too. The
  screenshots of the main window at Min and Default show the panes together, for review.
- While a photo is cropped, `CropControls` float over the bottom of the photo's surround, and the photo
  being cropped fits above them. Where the photo pane is too narrow for one row (the window's Min with
  the inspector open), the straightening takes a row of its own above the rest. Seen in the built app
  at 900 pt with the inspector, and at the default size; no layout test measures the floating
  controls.
- The zoom floats on glass over the bottom trailing corner of the photo, with the strip shown or hidden
  (about 390 pt wide). At the window's Min the photo pane is 580 pt wide with the inspector at its ideal
  width, so it fits; it covers a corner of the photo, as the user chose. Seen in the built app at
  900 pt with the inspector.
