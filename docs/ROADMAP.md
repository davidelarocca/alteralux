# Roadmap

What is done, what is being done and what comes next. Keep it current: it is where a new session starts.
Where the product is going, and what version 1.0 means, is in [VISION.md](VISION.md).

## Done

- **Engine bridge** (`engine/crates/alteralux-ffi`): the upstream engine exposed to Swift through UniFFI,
  with tests that compare its output with the upstream pipeline.
- **AlteraluxKit**: image decoding (RAW through `CIRAWFilter`, each preview decoded at its size),
  white balance for RAW files, settings, rendering, export with color management, covered by tests on
  the real engine.
- **The app**: one window with the viewer (zoom, fit, 100%), the strip of open photos, comparison with the
  original, the adjustments inspector and export. English and Italian. Sandboxed.
- **Structure**: design system and screens in Swift packages, the app target as a shell.
- **Formatting**: the Swift code is formatted with `swiftformat` (`.swiftformat`). `LayoutContract.swift`, copied
  from the swift-harness templates, is excluded so it can still be compared with the plugin's copy.
- **CI**: Rust tests on Linux; on macOS the engine build, the checks of `scripts/verify.sh full`, a launch
  smoke test with a screenshot, and the packaged app as an artifact.

## Verified, and not yet verified

- Verified by tests: the bridge does not change the engine's pixels; row and channel order end to end;
  parameter mapping; size, bit depth and embedded profile of exported files.
- Verified on a CI Mac: the app builds, launches, opens an image and shows it developed.
- Verified by driving the built app on a Mac (2026-11-19, through its menus and controls, with generated
  pictures of 1.5, 24 and 1.5 megapixels, one stored rotated): opening a photo, orientation, the strip,
  previous and next, fit, 100%, zoom in and out, comparison with the original, every slider and toggle,
  adjustments kept per photo, reset, slide and negative films, the window's minimum size, the inspector
  toggle, export to JPEG (sRGB) and 16-bit TIFF (Display P3) with the expected size, depth and profile,
  removing photos.
- Measured on an Apple M5 with 16 GB (generated 16-bit TIFF, GPU backend): a preview update takes about
  0.1 s at any size; the full-resolution render for the 100% view and for export takes about 0.6 s at
  12 MP, 1.8 s at 24 MP, 5.3 s at 45 MP and 9.2 s at 60 MP.
- Measured on the same Mac on 2026-11-20, where the time of one preview update at 2048 px went (24 MP
  source, default settings): 60 to 70 ms of GPU work (25 ms with every effect off; halation adds 18,
  the couplers 15, sharpening 4, grain 2), 6 ms to prepare and read back, 12 ms to copy the pixels
  into Swift (1 ms in Rust: the rest is the bridge's copy), and 31 ms on the main thread to put the
  frame on screen, because of the layer's mipmaps. Moving the exposure, the print filters or the
  preflash adds 9 ms: the engine recalibrates the pipeline, and 7.5 ms of that is upstream reloading
  its spectral table and rebuilding its lookup table (loading the two profiles is 0.8 ms). At 1024 px
  the whole engine call takes 15 to 25 ms. Scaling the 24 MP source for a preview size takes about
  250 ms, once per size. In a large window on a 4K display the fitted photo needs
  more than 2048 px, so every update was a full-resolution render: 1.0 to 1.2 s at 24 MP.
- Measured on the same Mac on 2026-11-20, one preview update of a 24 MP source by size, once the
  source is scaled for it: 90 ms at 2048 px, 145 at 2560, 230 at 3072, 320 at 3584, 450 at 4096,
  740 at 5120, 1050 at full resolution. Scaling the source for a size takes 250 to 370 ms, once.
- Measured on the same Mac on 2026-11-20 with a real RAW (Sony ILCE-7M3, 24 MP, a public-domain sample
  from raw.pixls.us), before and after
  [ADR 0007](adr/0007-decode-each-preview-at-its-size.md). Before: the first picture 1.6 s after
  opening (1.15 s to decode the whole photo and hand it to the engine, 0.45 s for the first preview).
  After: the first picture in 0.4 to 0.6 s; a temperature drag shows a frame every 90 ms at 1024 px
  and the settled preview 0.35 s after the release; an exposure drag shows a frame every 32 ms; a
  zoom to 100% takes 1.2 s once the whole photo is decoded, which happens ahead of need.
- Verified by driving the built app on 2026-11-20 with the same RAW and a 24 MP TIFF: the RAW opens
  and is developed with the right orientation and plausible colors; temperature and tint start from
  the camera's values (4490 K, 8), a lower temperature turns the photo cooler and a higher one
  warmer, Reset Adjustments goes back to the camera's values, each photo keeps its own white balance
  when the selection changes, and on the TIFF the two sliders are dimmed, do not move and carry
  their note. It is the only camera file tried so far.
- Verified by driving the built app on 2026-11-20: adjustments made on a RAW are in the photo's
  extended attribute and come back after quitting and opening the photo again; a photo made read-only
  keeps them in the app's container and gets them back too; two changes are undone and redone as two
  steps by the toolbar's buttons and by Command-Z and Shift-Command-Z; the toolbar fits the window at
  its minimum size.
- Verified on 2026-11-20 with a throwaway probe app signed with this app's two entitlements: inside a
  folder handed to the app, a security-scoped bookmark is resolved again after a relaunch, files are
  listed, read, moved, copied and trashed, Finder tags and extended attributes are read and written,
  a file can be created beside a photo, and changes are reported by FSEvents. No entitlement has to
  be added for the library. Moving into a folder that was not handed over fails (Cocoa error 513).
- Measured on 2026-11-20 on 40 RAW and 40 TIFF files of 24 MP, for a 480 px thumbnail: from the
  preview embedded in a RAW, 12 ms a file (0.15 s for 40, eight at a time); from a TIFF, 0.6 s a file
  whatever the way, 4.7 s for 40 with ImageIO eight at a time and 20 s with QuickLook, which does not
  gain from concurrency.
- Verified by driving the built app on 2026-11-20: a folder opened from the Finder is added to the
  library and shown (eight photos, an upright one whole, a folder inside it in the list); a photo is
  developed from the grid with the folder's photos in the strip; back in the library it has its
  mark; after quitting, the app opens on the library with the folder remembered.
- Verified by driving the built app on 2026-11-20: a selected photo brings up the bar of actions;
  discarded, it leaves the grid (seven of eight), carries the mark as an extended attribute and is
  still on disk; the counts read right in Italian ("1 selezionata").
- Verified by driving the built app on 2026-11-20, on a folder of test pictures: a recipe saved from
  the toolbar (the name asked, the Save button waiting for it) is a file in the app's folder without
  a white balance; given to another photo it changes its film, is written into the photo, and is
  undone and redone from the toolbar; from the library's bar it reaches the selected photo and Undo
  in the Edit menu takes it back; Copy Adjustments and Paste Adjustments give a photo the look of
  another, with its mark in the grid, and Undo leaves it without adjustments and without mark; the
  export of a selection writes into "Sviluppate" beside the originals under the name of the photo
  and its film, a 24-megapixel picture at its full size, with the progress on screen; the bar of
  the selection in Italian at the smallest window. This was before the recipes became a menu and
  the export sheet took its new shape: those two are covered by tests and snapshots, not yet seen
  in the built app.
- **Not verified yet**: several photos selected at once in the built app (a recipe and an export for
  many are covered by tests of the app model); the export into a folder chosen in the panel; stopping
  an export halfway; the menus of the bar (Move to, Copy to, Tag) and the emptying into the Trash by
  hand in the built app (they are covered by tests of the app model); RAW files of other cameras, their
  highlights and metadata; how a white balance drag feels under the hand (it is timed through the app
  model, not by hand); drag and drop, trackpad gestures, and the Open panel.

## Next, in this order

Decided on 2026-11-19, towards version 1.0 as described in [VISION.md](VISION.md). One branch and one
pull request per step, or per part of a long one; a merged branch is deleted.

1. **Defects found by driving the app.** Fixed on 2026-11-19, each with tests and checked again on the
   built app: several files opened at once, the keyboard and accessibility steps of `ParameterSlider`,
   black and white films printed on a color paper, the export file name, and commands enabled with
   nothing to act on. Fixed on 2026-11-20: a black and white paper no longer shows the yellow and
   magenta filters, and the film and the paper measured at several development times (Kodak
   Double-X, Kodak 2302) offer them, the middle one first; checked in the built app, where 12 minutes
   gives a brighter, harder print than 4.
2. **The interface redrawn** in the visual direction of the vision: the structure the mockups of
   2026-11-20 settled, built from the system's controls
   ([ADR 0006](adr/0006-use-the-systems-controls.md)). Done: the slider (the system's, filled from the
   neutral point, with keyboard and accessibility by step), the film as the heading and its list with
   an emblem per film, collapsible sections that show their values, previous and next in the toolbar
   beside the window's title, the zoom controls under the photo, with snapshots and `KeyboardCheck`
   tests. Changed on 2026-11-20 night, seen in the built app: the toolbar's buttons in four groups
   (undo and redo; crop and the original; Recipe and export; the adjustments), the zoom on the row
   of the strip, at its trailing end, and the paper's name written whole under its caption; the
   size and time of each render are no longer on screen but in the system log (category
   `render`). The sliders keep their title above them: one row per slider was proposed and
   turned down. The film list has the system's search field (`SearchField`, with the
   magnifying glass and the button that clears it), no lines between the films, and grows
   with the window: 13 films in view at the default size instead of 8. The zoomed photo's
   scroll bars are the thin ones that show while scrolling, even with a mouse connected, and so
   are the panels' (`thinScrollBars()`: the adjustments, the library, its folders, the films).
   A mouse's wheel zooms the photo about the pointer, two fingers on a trackpad move it, and
   Command with any scroll zooms (a Magic Mouse scrolls as a trackpad does); a drag moves a
   photo larger than the view, with the hand pointer. The crop's controls float over the bottom of the photo on the system's
   glass (`GlassGroup`): the shape of the frame, which opens its list upward inside the window,
   upright or lying down, turn, mirror, the straightening in degrees on one row and Reset, with
   Cancel and Done round beside them; on a narrow window the straightening takes a row of its
   own. Controls in the toolbar were tried and turned down. The zoom floats on the same glass
   over the photo's bottom trailing corner, and the library's selection bar is on glass too; the
   titles of the buttons on glass are white, dimmed only when disabled. The toolbar's Recipe
   button is its symbol alone; its menu opens inside the window and has no submenus: renaming
   and deleting moved to a sheet, Manage Recipes…. The inspector's pop-up buttons (paper, film
   format, development times) are `WindowPopUp`s: their menus stay inside the window near its
   edges. Still open:
   - The toolbar's other items of the vision arrive with their steps: the way back to the folder
     (step 6), undo and redo (step 5), crop (step 8), Recipe (step 7). Until the library exists, Open
     stands where the way back will be.
   - Done on 2026-11-20: View > Show Strip (Option-Command-S) hides the strip of thumbnails for
     more room, and the choice is kept.
3. **Immediate editing.** Measured on 2026-11-20 (see above). Done: the viewer no longer builds
   mipmaps for every frame; while the settings change the preview is rendered at 1024 px, then at the
   size the viewer needs; `PreviewBudgetTests` keeps a preview update under 50 ms at 1024 px and under
   200 ms at 2048 px on a Mac's GPU (on CI, whose virtual GPU is several times slower, it checks only
   that the lighter preview costs much less than the standard one); the preview is rendered at the
   size the viewer shows the photo, in steps of 512 px from 2048, so a photo fitted in a large
   window gets 2560 or 3072 px and not the full resolution (`PreviewSize`). Still open, in this
   order:
   - Let a lighter render overtake a slow one in progress. Measured on 2026-11-20: the engine has
     no way to stop a render, and a 1024 px render asked 100 ms into a full-resolution one of 24 MP
     (1.05 s) waits 730 ms, for the GPU, even from another thread. Done here: a slow render starts
     only after the settings have been still for a while, so a short pause does not start one. What
     is left is upstream: a way to abandon a render between its stages.
   - No round trip of the pixels through main memory (see "GPU texture sharing" and "100% view" below).
   - The 7.5 ms of recalibration on exposure, filters and preflash are inside the upstream engine: to
     propose upstream, not to patch here.
   - Not measured yet: what SwiftUI redraws while a slider moves (needs Instruments on the app).
4. **White balance** (temperature and tint) from the RAW decoder. Done: two sliders at the top of the
   Camera section, starting from what the camera recorded, for RAW files only (other files show, in
   their place, one line that says so); every preview decoded at its size by a decoder kept for the photo
   ([ADR 0007](adr/0007-decode-each-preview-at-its-size.md)); tests on a RAW the tests write
   themselves. Still open:
   - The temperature slider is linear in kelvin, so the warm end is cramped: to judge in the app.
   - The original shown for the comparison is the system's rendering, with the camera's white balance
     and at 2048 px at most.
   - A picker on the photo for the neutral point, and an automatic white balance (the vision's open
     question for adaptive recipes).
5. **Edits that persist**, with undo and redo. Done: each photo's adjustments are kept in the photo
   itself, as an extended attribute, and in a folder of the app's when the photo cannot be written
   ([ADR 0008](adr/0008-keep-edits-in-the-photo.md)); they are read back when the photo is opened;
   undo and redo through the window's own undo manager, one step per change, with two buttons in the
   toolbar. Still open:
   - A sidecar beside the photo, for services that drop extended attributes: possible only inside
     folders the user adds, so with the library.
   - Undo steps are not kept between launches.
   - Fixed on 2026-11-20: in Italian Redo read "Ripristina", just above "Ripristina regolazioni"; it is
     "Ripeti", as macOS says it.
6. **The library**: the folders the user adds, shown as they are on disk, a grid of their photos, and
   the actions on a selection (move, copy, tag with the Finder's tags, discard). Done, the first part:
   folders added from a panel, the File menu, a drop or the Finder, and remembered between launches;
   the list of folders with the ones inside them and their counts; the grid with names, a mark on the
   photos that have adjustments and a filter for them; the size of the thumbnails; a double-click or
   Return to develop, with the folder's photos in the strip, and the way back in the toolbar; changes
   on disk noticed. The second part: with photos selected, a bar to move and copy them to another
   folder of the library, to put Finder tags on them (on, off or mixed for a selection) and to discard
   them; discarding marks a photo in the photo itself and hides it, a filter shows the discarded ones,
   where they are taken back or emptied into the Trash after a confirmation; discarding and moving
   can be undone. Still open:
   - Moving and copying go only to folders of the library: a destination outside it has to be added
     first. Copying and tagging are not steps of undo.
   - The grid shows the camera's own preview, not the developed look: that needs a render per photo
     and a cache.
   - Fixed on 2026-11-20: the arrow keys move in every direction, a folder that cannot be added
     says why, and the thumbnails kept on disk are pruned at launch to 512 MB, oldest first.
   - A sidebar entry for photos opened one by one, outside any folder.
   - Recipe and export for a selection come with step 7.
7. **Recipes** (the looks of earlier notes): save and apply, copy between photos, export several
   photos, adaptive to exposure and temperature. Done, the first part
   ([ADR 0009](adr/0009-recipes-are-looks-kept-by-the-app.md)): a recipe is a look under a name,
   everything but the white balance, kept by the app; one Recipe menu, in the toolbar and in the bar
   of the library's selection, gives a recipe to the photo on screen or to the selected photos (one
   undo takes it back from all), saves the look on screen as a new recipe, renames and deletes;
   Copy Adjustments and Paste Adjustments in the Edit menu; the selected photos of the library are
   exported in one go, each with its own adjustments, at the original size or a smaller one, into a
   folder "Developed" beside the originals or into one folder, asking whether to replace, keep both
   or skip when the photos were exported there before (with the same film or another), with one progress, a way to stop,
   and at the end only the photos that failed. Sheets share one shape (`FormSheet`), drawn after the
   system's alert. Still open:
   - Adaptive recipes: done on 2026-11-21 ([ADR 0011](adr/0011-recipes-adapt-to-each-photo.md)). A
     recipe can adapt to each photo (a switch in the recipe sheet): given to a photo, it turns the meter
     on and the white balance to automatic, unless the photo's was chosen by hand. A "Automatic white
     balance" switch in the Camera section measures the photo's light and keeps the camera's white
     balance unless it is far off. Seen in the built app on the test RAW. Changed the same day after
     measuring 126 of the user's RAWs: a white balance the camera chose itself is kept (ADR 0011).
     Still to judge on real photos whose white balance was set by hand: the thresholds.
     Moved on 2026-11-21 from the recipe to the workflow, at the user's request
     ([ADR 0014](adr/0014-finder-and-shortcuts-hand-photos-to-the-app.md)): a recipe given in the app is
     given as it is, and a workflow says whether it adapts.
   - Recipes are in the order of their names, and deleting one asks first but is not a step of undo.
     Recipe files cannot be imported or handed to someone else yet.
   - The export's progress is the system's bar, not the print coming up in the developer of the
     vision. Photos opened one by one, outside the library, are exported one at a time.
   - Fixed on 2026-11-20: a photo of the strip that receives a recipe from the library showed its
     old look in the strip until it was opened; it is developed small at once.
8. **Crop and straighten.** Decided on 2026-11-20
   ([ADR 0010](adr/0010-crop-before-the-engine.md)): the photo is framed before the engine, so the
   grain keeps its size relative to the finished picture; the frame belongs to the photo, not to
   recipes. Done: Crop in the toolbar, in the photo's menu and in the Edit menu (Option-Command-C)
   shows the whole photo developed with a frame over it, as Photos does: its edges, corners and
   inside are dragged; a shape (free, the photo's own, square, 4:5, 2:3, 9:16, upright or lying
   down); a slider straightens the photo up to 45 degrees either way, and the frame shrinks to stay
   inside the turned photo and comes back when it is turned back; Reset, Cancel (Escape) and Done
   (Return), which is one step of undo. The previews, the 100% view, the strip and the exports are
   all of the framed picture. Seen in the built app on 2026-11-20 with real pointer drags. Also
   done: a quarter turn to the left and a mirror, in the crop bar, before the straightening (seen
   in the built app). Return and Escape were tried by the user in the built app. Still open: the
   library's thumbnails show the whole photo, as they show no other adjustment.
9. **Camera and lens corrections.** Brought forward on 2026-11-21 together with step 10, at the user's
   request: workflows, adaptive recipes and lens corrections arrive together, in this order. Done, the
   first part ([ADR 0011](adr/0011-recipes-adapt-to-each-photo.md)): a "Lens correction" switch in the
   Camera section, on for new photos, applied by Apple's RAW decoder where it knows the lens, with a
   line that says so where it does not; photos developed before keep what the decoder did on its own.
   Done, the second part ([ADR 0012](adr/0012-lens-profiles-from-lensfun.md)): for the RAWs whose lens
   Apple's decoder does not know, lensfun's database (`third_party/lensfun`, unmodified, CC BY-SA 3.0,
   credited in the About panel and the README), read at launch in a fraction of a second; the camera
   and lens the photo names are matched as lensfun matches them, the corrections interpolated at its
   focal length, aperture and distance, and applied by a Core Image kernel (distortion with the
   picture enlarged to fill the frame, colored fringes, vignetting) before the frame; the inspector
   names the profile. Seen in the built app on a test RAW that names a Sony A7 III and the FE 24-70mm
   GM. Measured on 2026-11-21 on 126 of the user's RAWs (numbers only): a Sony ZV-E10 with a Viltrox
   56mm F1.7 E, which neither Apple's decoder nor lensfun knows.
   Done, the third part ([ADR 0015](adr/0015-the-cameras-own-lens-corrections.md)), asked by the user
   on 2026-11-21 for every maker, vignetting included: the corrections Sony, Fujifilm, Nikon Z,
   Olympus/OM System and Panasonic cameras record in each RAW, read as darktable and ART read them and
   applied by a kernel of their own; the geometry by Apple's decoder, then the camera, then lensfun;
   the vignetting by the camera wherever Apple's decoder leaves it (always for Sony and Fujifilm),
   then lensfun. The readings match Apple's own correction to a few pixels on samples of every maker.
   All 920 of the user's Sony RAWs carry them; the Viltrox 56mm and 25mm on the ZV-E10, which nobody
   corrected, now are. Not read: older Sony bodies' enciphered block; Canon records nothing readable;
   DNG opcodes are Apple's decoder's. To be judged by the user's eye: Sony's vignetting, on a plain
   sky or wall at full aperture (the least certain reading; ART's, about -1 EV in the corners at f/1.4). Still open: how well lensfun covers the user's own lenses, and the look of the correction on
   real photos; photos that are not RAW are not corrected (their camera may have done it already).
10. **Recipes and workflows, from the app and the Finder.** Decided with the user on 2026-11-21: a
   workflow is a recipe and what to do with it (format, size, where to save, such as a folder beside the
   originals). Recipes and workflows are managed in one window, each recipe with its workflows; renaming
   a recipe carries to its workflows and to Shortcuts, deleting one names the workflows that use it.
   From the Finder: "Develop with alteralux…" in the right-click menu (a Services entry, no extension:
   a probe app showed an extension cannot read the app's workflows without an App Group, which needs a
   developer team), which develops them at once with the workflow chosen;
   the first time in a folder outside the library the app asks for access to it, once (the sandbox
   denies a folder beside the originals otherwise). Shortcuts gets a "Develop Photos" action with the
   same workflows.
   Done, the first part ([ADR 0013](adr/0013-workflows-are-recipes-with-their-files.md)): the Recipes and
   Workflows window (the Recipe menu and the Window menu), with the recipes in a list and, for the one
   chosen, its film and paper, whether it adapts to each photo, Rename and Delete, and its workflows, each
   made and changed in a sheet with the export's own options and a destination (a folder of a given name
   beside the originals, or one folder chosen once); in the library, the selected photos are developed
   with a workflow from the selection's bar or a photo's menu, through the export sheet and its progress.
   A workflow only writes files: the photos keep their adjustments. Done, the second part
   ([ADR 0014](adr/0014-finder-and-shortcuts-hand-photos-to-the-app.md)), after the user tried a first
   version with a sheet and found it not immediate: a recipe is a look, and a workflow is how it is
   used (the recipe, whether it adapts to each photo, the files, their names, and beside the photos, in
   a folder beside them or in one folder). "Develop with alteralux…" in the Finder's right-click menu
   develops the selected photos at once: with the only workflow, or with the one chosen in a list at the
   pointer; the files appear without a question, and nothing beside the photos is ever replaced. A
   folder outside the library is asked for once. Shortcuts has "Develop Photos": photos and a workflow
   in, the files written out. Checked in the built app on test pictures: the entry registered with its
   Italian title, one workflow developing at once, the list with two, the permission asked once and
   kept, the files beside the photos and in a folder beside them, the app that sent them back in front.
   Then, at the user's request, invisible: a workflow can leave its format, size, file names and
   destination open, asked each time; from the Finder, a workflow that settles everything develops
   with no window and no Dock icon, and the app quits after; otherwise a small panel at the center of
   the screen asks only what is open (or makes the first workflow). Still to be seen by the user: the
   action in the Shortcuts editor. Later, with a developer team: each workflow as an entry of the
   Finder's menu, through an extension.
11. **The rest of the harness**, spread over the steps above where it helps: a UI test target
   (`AccessibilityAudit`, `LayoutAudit`, `FocusOrder`) that makes the checks of step 1 permanent, then
   `SCHEME_HAS_TESTS=1` in `scripts/verify.sh`; pane measurements for `docs/LAYOUT_CONTRACT.md`;
   `/swift-harness:product-map` and `/swift-harness:audit`.
12. **Version 1.0**: the icon, the notarized release.

### Before step 8: the design, as the user sees it in the running app

Said on 2026-11-20 by trying step 7 in the running app, and proposed as the next piece of work, on a
branch of its own. What was said, in the order to take it:

- The library's page, drawn first as mockups the user approved. Done: the filter (All, With
  Adjustments, Discarded) in the middle of the toolbar; a Filter and Sort menu at its trailing side
  (by name, date or kind, ascending or not; RAW or the other kinds; one Finder tag), opening inside
  the window; the photos in rows that reach both edges of the grid, as in Photos, each as wide as
  its own shape, so an upright photo is no longer in a wide tile; a dot for each colored Finder tag beside a photo's name and a small mark on a discarded
  photo, which stays hidden outside its own filter; the actions on the selection in a bar floating
  over the grid; up and down arrows; under the grid, the size of the photos shown or of the selected
  ones; a rectangle dragged over the grid selects photos; a list of tags in the Finder's manner, with
  a field that narrows it and makes a tag with a color; a photo opens with the adjustments closed.
  Seen in the built app on 2026-11-20: the tag list, a new tag made with a color and written to the
  file, a photo opening without the adjustments; with real pointer events on a folder of 40 test
  pictures, a click on a photo and between them, a rectangle that scrolls the grid when held at its
  bottom edge, and the arrow keys bringing the photo they reach in sight. The date is the one the
  photo was taken (the file's for a photo that does not say), and the order and the filters (what
  is shown, the kinds, the tag) are kept between launches. Still open: one tag at a time.
- Mouse and keyboard, asked on 2026-11-20 ("everything must feel intuitive"). Done, checked in the
  built app: Shift with the arrows, Home, End, Page Up and Down in the grid; Space for Quick Look;
  Zoom In and Out and a pinch for the thumbnails; a menu on a secondary click on a photo, in the
  grid and while developing; Escape from a developed photo back to the library; the View menu's
  items for the developed photo turned off in the library; holding M shows the original while
  developing, as in Photos; typing the beginning of a name in the grid goes to that photo, as in
  the Finder. Holding M and typing a name were tried by the user in the built app. Still open: the
  pinch was not tried on a trackpad.
- The library's details, gone through with the user on 2026-11-21: the status line without the
  double-click hint; a photo's menu with everything the bar has and the Finder's actions on the
  file (Open With, Share, Duplicate, Rename, Tags with their colors, Move to Trash), Reset
  Adjustments, Rotate Left and Right (the grid's thumbnail turns with the photo), Move to Trash after
  a confirmation (undo cannot bring photos back from the Trash; the Finder can), and the number of
  photos in the titles when it acts on several; while developing, the left and right arrows go
  through the photos (the View menu's arrows never reached the app), and a click on a slider takes
  neither the arrows nor draws a focus ring (the sliders take the keys only with the system's
  Keyboard navigation on); the strip ends at the adjustments' edge instead of running on under
  their glass.
- Things that reach past the window's edge when the window is made small: to find one by one in
  the running app, at the sizes of `docs/LAYOUT_CONTRACT.md`, and fix. Checked on 2026-11-20 at the
  smallest window (900 × 600), in Italian: the develop screen with the adjustments open, the export
  sheet, the list of films, the library with its sidebar, the bar of the selection and its list of
  tags all stay inside. The user's own examples are still to be asked for.
- One look for what asks and what answers: the system's alert (bold title, wide round buttons)
  is the reference the user likes; `FormSheet` follows it. The rest of the app is to be gone
  through the same way, screen by screen, shown to the user before it is built.
- The controls the app adds to the engine's own, asked on 2026-11-21 ("rivedere i controlli extra
  che abbiamo aggiunto rispetto a spektrafilm… organizzarli meglio"). Decided with the user on
  2026-11-21 ([ADR 0016](adr/0016-develop-in-the-order-of-the-analog-process.md)): the inspector in the
  order of the analog process, Shot (what is set before the film: exposure and metering, white
  balance, lens, cropping), Film, Print, Scan. Done, the first part: the four sections, and an
  exposure that brightens (the engine's lab compensated it at the print; now a switch of the print,
  off for new photos, on for those saved before). Seen in the built app on the test card: +2 EV
  brightens it. Next, the second part: every control spektrafilm offers and the app hides (diffusion
  filter, DIR couplers, glare, preflash, print curves, halation and grain details, scanner levels,
  metering method), the technical ones under "More adjustments"; then the third: highlight recovery
  and noise reduction from Apple's RAW decoder in Shot. Retouches after the scan: later.

After 1.0, in an order still to decide: the Photos integration, more of the engine's parameters behind
an "advanced" section.

Defects found on real RAW files go to step 1.

## Open questions

- **Export precision.** Upstream offers an f64 CPU build for exact parity with Python. f32 and f64 builds
  cannot share one static library, so if the difference turns out to be visible the f64 engine would ship
  as a separate helper (an XPC service) used only for export.
- **Photos extension.** As far as we know, Photos hands editing extensions a rendered image rather than
  the RAW original, which would lower the quality compared with the app (the app can read originals from
  the library through PhotoKit). To verify first thing when the Photos integration starts.
- **GPU texture sharing.** Previews currently travel GPU → CPU → GPU. If that becomes the bottleneck, wgpu
  can render into an `IOSurface` shared with the viewer's layer.
- **100% view.** Zooming in renders the whole photo at full resolution. The engine has no
  region-of-interest rendering yet; rendering only the visible area would make large photos much faster.
- **RAW highlights.** `CIRAWFilter` is used with its tone curve off. Whether its extended dynamic range
  setting should be raised to keep more highlight detail needs a look at real files.
- **Distribution.** The app is signed to run locally, and CI packages it as an artifact. Giving it to other
  people needs a Developer ID signature and notarization, which need an Apple developer account. The Mac
  App Store is excluded ([ADR 0001](adr/0001-reuse-the-rust-engine.md)).
- **XcodeGen projects in swift-harness.** The plugin reads build settings from a committed project file;
  here the project is generated, so the signing settings were moved to an `.xcconfig`.
