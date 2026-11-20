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
- **Not verified yet**: RAW files of other cameras, their highlights and metadata; how a white
  balance drag feels under the hand (it is timed through the app model, not by hand); drag and drop,
  trackpad gestures, and the Open panel.

## Next, in this order

Decided on 2026-11-19, towards version 1.0 as described in [VISION.md](VISION.md). One branch and one
pull request per step, or per part of a long one; a merged branch is deleted.

1. **Defects found by driving the app.** Fixed on 2026-11-19, each with tests and checked again on the
   built app: several files opened at once, the keyboard and accessibility steps of `ParameterSlider`,
   black and white films printed on a color paper, the export file name, and commands enabled with
   nothing to act on. Still open:
   - With a black and white print the yellow and magenta filters stay visible, and the development
     times the black and white profiles carry are not offered.
2. **The interface redrawn** in the visual direction of the vision: the structure the mockups of
   2026-11-20 settled, built from the system's controls
   ([ADR 0006](adr/0006-use-the-systems-controls.md)). Done: the slider (the system's, filled from the
   neutral point, with keyboard and accessibility by step), the film as the heading and its list with
   an emblem per film, collapsible sections that show their values, previous and next in the toolbar
   beside the window's title, the zoom controls under the photo, with snapshots and `KeyboardCheck`
   tests. Still open:
   - The toolbar's other items of the vision arrive with their steps: the way back to the folder
     (step 6), undo and redo (step 5), crop (step 8), Recipe (step 7). Until the library exists, Open
     stands where the way back will be.
   - The setting that collapses or hides the strip of thumbnails.
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
   Camera section, starting from what the camera recorded, for RAW files only (other files show them
   disabled, decided on 2026-11-20); every preview decoded at its size by a decoder kept for the photo
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
   - In Italian the Edit menu shows "Ripristina" (Redo) just above "Ripristina regolazioni" (Reset
     Adjustments): the second needs another word.
6. **The library**: the folders the user adds, shown as they are on disk, a grid of their photos, and
   the actions on a selection (move, copy, tag with the Finder's tags, discard). Needs step 5, and the
   open questions of the vision on where marks are kept and on tags in the sandbox.
7. **Recipes** (the looks of earlier notes): save and apply, copy between photos, export several
   photos, adaptive to exposure and temperature.
8. **Crop and straighten.**
9. **Camera and lens corrections**, after the open question on their source.
10. **Workflows from the Finder**: Shortcuts actions that develop the photos they receive with a recipe
   and return the files, so the shortcut saves them (for example in a subfolder beside the originals)
   and can run as a Finder Quick Action. Needs steps 7 and 9.
11. **The rest of the harness**, spread over the steps above where it helps: a UI test target
   (`AccessibilityAudit`, `LayoutAudit`, `FocusOrder`) that makes the checks of step 1 permanent, then
   `SCHEME_HAS_TESTS=1` in `scripts/verify.sh`; pane measurements for `docs/LAYOUT_CONTRACT.md`;
   `/swift-harness:product-map` and `/swift-harness:audit`.
12. **Version 1.0**: the icon, the notarized release.

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
