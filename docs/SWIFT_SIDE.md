# The Swift side

What each Swift module does and how the app works at run time.
Hub: [ARCHITECTURE.md](ARCHITECTURE.md).

### `AlteraluxKit` (Swift package)

- **`AlteraluxEngine`**: the generated UniFFI bindings plus the compiled
  engine as an XCFramework. Nothing else.
- **`AlteraluxKit`**: what an app needs, without any UI.
  - `ImageLoader` decodes a file to scene-linear Rec. 2020 float pixels. RAW
    files go through `CIRAWFilter` with tone curve, local tone mapping, gamut
    mapping and sharpening turned off; other formats go through ImageIO. It
    also provides the system's default rendering of a file, used for
    thumbnails and for the before/after comparison. A DNG the system's
    decoders refuse for a fault in its tags is handed to them mended in
    memory (`MendedDNG`: the five-byte version tags of the DJI Osmo Action).
  - `PhotoDecoder` (an actor) is the decoder of one open photo. It keeps the
    `CIRAWFilter` between calls and decodes the photo at the size asked and,
    for a RAW, with the white balance asked; it reports the white balance the
    camera recorded. The decoder scales the photo itself: a preview costs a
    fraction of the whole photo
    ([ADR 0007](adr/0007-decode-each-preview-at-its-size.md)).
  - `DevelopSettings` carries the white balance as an optional temperature
    and tint, where `nil` is "as the camera recorded". They are not part of
    the engine's patch.
  - `SceneTone` is the scene's highlights and shadows, changed after the
    meter and before the film
    ([ADR 0019](adr/0019-highlights-and-shadows-before-the-film.md)): a gain by
    luminance that a Core Image kernel (`SceneToneKernel`) puts into the
    pixels, in `PhotoDecoder`. With the meter on, the decoder first asks the
    engine what its meter reads (`SourceImage.meteredEv`) for the photo as it
    was shot, decoded small: whole, with the camera's white balance and the
    decoder's own choices, whatever the adjustments
    ([ADR 0022](adr/0022-the-automatic-modes-read-the-photo-as-shot.md)). It
    puts that exposure into the pixels and marks the result
    (`LoadedImage.isMetered`); `FilmRenderer` then exposes it with the meter
    off. With the exposure by hand and the two left at zero, none of this runs.
    The automatic white balance (`AutomaticWhiteBalance`) is measured on the
    photo as it was shot too.
  - `DevelopSettings` is the app's model of an edit (`Codable`). It converts to
    the engine's JSON patch; tests check that the engine accepts it and that
    each value lands on the intended parameter.
  - `EditStore` keeps a photo's adjustments between launches: in an extended
    attribute of the photo, or in a folder of the app's when the photo cannot
    be written ([ADR 0008](adr/0008-keep-edits-in-the-photo.md)); what is in
    that folder is later than what the photo carries, and is read first as
    long as it was kept for the file now at that path. Beside the
    adjustments it writes the film model they were saved with
    (`FilmModel.version`, the upstream engine's version), and a `Recipe`
    carries the one its look was made with, which a rename keeps: an engine
    update may change what the same adjustments look like, and this is what
    tells an earlier look apart. Nothing reads it yet; what was saved before
    has none.
  - `Recipe` is a look under a name: every value of `DevelopSettings` but
    the white balance, of which it keeps only whether it was automatic.
    It also holds the files it writes when photos are developed with it
    (`RecipeFiles`: format, size, names, destination, and what is asked
    each time). `RecipeStore` keeps the recipes in a folder of the
    app's, one JSON file each
    ([ADR 0009](adr/0009-recipes-are-looks-kept-by-the-app.md),
    [ADR 0021](adr/0021-a-recipe-holds-its-files.md)). `WorkflowMigration`
    turns the workflows kept before into recipes, once.
  - The library, in `Library/`: `LibraryFolders` remembers the folders the user
    added (security-scoped bookmarks in a property list) and holds their
    access; `FolderContents` reads a folder's tree and its photos, in the
    Finder's order; `FolderWatcher` reports changes on disk (FSEvents,
    coalesced); `ThumbnailProvider` makes thumbnails with ImageIO, from the
    preview embedded in the file when there is one, a few at a time, kept in
    memory and on disk; `PhotoFileActions` moves, copies and trashes files
    and reads and writes their Finder tags, reporting per file; `DiscardStore`
    keeps a photo's "discarded" mark in the photo, like its adjustments;
    `PhotoInfoReader` reads what the grid shows and sorts a photo by, without
    decoding it: its shape, the date it was taken, whether it is a RAW, its size and its
    Finder tags with their colors.
  - `FilmRenderer` runs renders on its own queue, off Swift's cooperative
    thread pool, and wraps the result in a `CGImage` tagged linear sRGB.
  - `ImageExporter` writes JPEG, 10-bit HEIC, 16-bit TIFF and PNG through
    Core Image, converting to sRGB or Display P3 and embedding the profile,
    with the original's camera metadata. `BatchExporter` develops several
    photos one after the other, each decoded at the size it is exported at,
    and writes them beside the originals or into one folder. A photo exported
    before is recognized by its name with any film, in any format the app
    writes: its old files go to the Trash and the new one is written, or
    they are kept beside the new one, or the photo is skipped, as the caller
    says. Nothing is ever written over; it reports per photo and stops between photos when
    its task is cancelled.

The tests of the package run the real engine: they check row order and channel
order end to end, the bit depth and profile of exported files, and the
parameter mapping.

- **`AlteraluxUI`**: the app model and the screens, as a package target so
  they build and test with `swift test`, outside the sandboxed app.

Its tests (`AlteraluxUITests`) also draw in real windows, with the helpers
copied from the swift-harness templates (`LayoutContract.swift`,
`Screenshot.swift`, `Snapshot.swift`, `KeyboardCheck.swift`, kept as shipped):

- the layout contract of the main window (`docs/LAYOUT_CONTRACT.md`);
- snapshots of the shared components, compared with the approved images in
  `snapshots/` (pinned to the macOS version and display scale they were made
  on; elsewhere they are reported as not compared);
- screenshots of the main window, empty and with a developed photo, saved to
  `.build/swift-harness/screenshots/` for review and never compared.
- key presses on the shared components that promise keyboard actions.

These suites are nested in `WindowedTests`, which runs them one at a time.

### `DesignSystem` (Swift package)

Tokens (`Spacing`, `Radius`, `Typography`, `Motion`, semantic colors) and the
shared components. The only place for raw visual values: see
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) and [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md).

### The app (`apple/Alteralux`, `AlteraluxUI`)

A single-window SwiftUI app. The app target is a shell: the `@main` scene, the
resources, the entitlements. `AppModel` (`@Observable`, main actor) owns the
open photos, the settings of the selected one and its preview.

- **Rendering loop.** A settings change requests a render. Requests made while
  a render is running collapse into one follow-up render with the latest
  settings, so dragging a slider never queues stale frames.
- **Sources.** Opening a photo creates its `PhotoDecoder`; no pixels are
  decoded yet. Each render asks `PhotoSources` for the photo at the size it
  renders, and the engine scales nothing. `PhotoSources` keeps three reduced
  sizes and the whole photo for the current white balance, and drops them
  when it changes. Once a settled preview is on screen it decodes ahead the
  1024 px size, then, after a quiet second, the whole photo for the 100% view
  and for export.
- **Library.** The window shows the library or the photo being developed
  (`AppModel.showsLibrary`); it opens on the library once a folder was added,
  unless the app was started on a photo. `LibraryModel` holds the folders
  with their trees and counts, the folder on screen, its photos, which have
  adjustments, what each says about itself (`PhotoInfo`), the filter, the
  order (name, date or kind), the kinds and the tag shown, and the selection; it reads off the main actor and
  reads again when a `FolderWatcher` reports. A photo of a folder is
  developed with the folder's photos in the strip, in their order, and the
  toolbar has the way back. Folders come from a panel, the File menu, a drop
  on the window or the Finder. The grid lays the photos in rows that reach both
  edges, each photo as wide as its own shape (`LibraryRows`), with a dot for each colored
  Finder tag beside the name; the toolbar has the filter in the middle and a
  Filter and Sort menu at the trailing side; the line under the grid says the
  size of the photos shown, or of the selected ones. Photos are selected as
  in the Finder: a click, Command and Shift with it, or a rectangle dragged
  from between them (`SelectionMarquee`), which scrolls the grid when held at
  its edge; a click between them clears the selection. The keys are the
  Finder's (`LibraryGridKeys`): arrows, with Shift to grow the selection,
  Home, End, Page Up and Down, Space for Quick Look, Return to develop,
  Delete to discard; Zoom In and Zoom Out of the View menu, and a pinch,
  resize the thumbnails. A photo has a menu of its own on a secondary click,
  in the grid and while developed (`PhotoMenus.swift`); Escape goes back from
  a developed photo to the library. With photos selected a bar floating over the grid offers the actions:
  move and copy to another folder of the library (the sandbox lets the app
  write only into folders the user added), Finder tags (a field over their
  list narrows it and makes a new tag with one of the Finder's colors; tags
  are written as the Finder keeps them, so a color stays), and discard, which
  marks a photo and hides it; the discarded photos have a filter of their
  own, where they are taken back or emptied into the Trash. Discarding and
  moving are steps of the window's undo.
- **Recipes.** `AppModel` holds the recipes. In the toolbar, while
  developing, they are a menu (`RecipeMenu`): choosing a recipe gives it to
  the photo on screen, as one step of undo kept at once; the look on screen
  can be saved as a new one, in a sheet that asks its name and shows the
  files it writes (`RecipeEditor`). Recipes are changed, duplicated and
  deleted in their window (`RecipesWindow`). Developing photos with a
  recipe writes its files and leaves their adjustments alone
  (`AppModel+RecipeFiles.swift`): from the library's selection, from the
  Finder and from Shortcuts (`AppModel+HandedOver.swift`). In the bar of the library's selection a list gives a recipe to
  every selected photo, in the strip or not, as one step of undo for all:
  `EditHistory.keep` writes them, and forgets the adjustments of a photo
  that had none when the step is undone. Copy Adjustments and Paste
  Adjustments in the Edit menu do the same with the look of one photo. A
  look never carries the white balance.
- **Export.** One sheet (`ExportSheet`, a `FormSheet`): for the photo on
  screen it is followed by the save panel; for the selected photos of the
  library it also asks where they go (a folder beside each original, or one
  folder) and, when files of an earlier export are there, whether to
  replace them, keep both or skip those photos; it stays while they are developed with one progress and a way to
  stop, and at the end names only the photos that failed.
  An exported file takes the name of its photo and of its film; a photo
  with a twin of another kind beside it, as a camera that saves RAW and JPEG
  leaves, names its kind too, so the two never write the same file.
- **Edits.** `EditHistory` follows the adjustments of the selected photo. A
  change is what happens between two moments of stillness (a whole drag, a
  film chosen, a reset): its first value registers one step in the window's
  `UndoManager`, and when the settings have stood still for 150 ms the
  adjustments are written with `EditStore`. They are also written when
  another photo is selected or a photo leaves the strip, and read when a
  photo is opened. Undoing a step of a photo that is not on screen selects
  it. The toolbar's two buttons and the Edit menu act on the same manager.
- **White balance.** Temperature and tint of a RAW, at the top of the Camera
  section. The sliders start from the camera's values and stop there: beside
  them the settings go back to `nil`, so "as shot" stays true on any photo.
  A file that is not a RAW shows, in their place, one line that says so.
- **Preview resolution.** The preview is rendered at the size the viewer shows
  the photo (`PreviewSize`): 2048 px on the long side while the photo is that
  small on screen, then larger in steps of 512 px, each shown enlarged by up to
  15% before the next is rendered, and the full resolution only when the
  viewer shows about that many pixels (at 100% always). A photo fitted in a
  large window is therefore rendered at 2560 or 3072 px, not whole. A photo
  selected after a fitted one starts at the same size. The viewer's zoom is
  measured against the full photo, so swapping previews does not move the
  picture.
- **While the settings change.** The preview is rendered at 1024 px, about a
  quarter of the work, so it follows a moving control. When the settings have
  stayed still for 150 ms the preview the viewer needs is rendered. One
  larger than 3072 px takes several tenths of a second, the full one a second
  or more, and the engine cannot interrupt a render (a lighter one asked
  meanwhile waits for the GPU): so the 2048 px preview stands in for it, and
  it is rendered only after that has been on screen for 400 ms with the
  settings still. A zoom made while the settings are still is not held back.
  The strip's thumbnail follows the settled preview only, and carries the
  library's mark (`PhotoMark`) once adjustments are kept with the photo
  (`PhotoItem.hasAdjustments`). The photo is
  decoded for the 1024 px preview as soon as it is on screen (see Sources),
  so the first move does not wait.
- **Viewer.** An `NSScrollView` (pinch, smart zoom, scroll) showing the
  `CGImage` through a layer. A mouse's wheel zooms about the pointer (a scroll with no gesture
  phase, or any with Command held), a trackpad's two fingers move the photo, and a drag moves
  a photo larger than the view. Core Animation color-manages it for the display.
  The layer reduces the image through mipmaps only below half size
  (`ImageScrollView.needsMipmaps`): see `docs/PITFALLS.md`.
- **Memory.** Only the selected photo's decoded pixels are kept; the strip
  holds small thumbnails.
- **Sandbox.** Access to opened files is kept for as long as they are in the
  strip, so their metadata can be copied at export time.

The Xcode project is generated from `apple/project.yml` and is not committed.
Code signing and hardened runtime settings live in
`apple/Alteralux/Signing.xcconfig`, a tracked file.
