# Roadmap

What is done, what is being done and what comes next. Keep it current: it is where a new session starts.
Where the product is going, and what version 1.0 means, is in [VISION.md](VISION.md).

## Done

- **Engine bridge** (`engine/crates/spektrafilm-ffi`): the upstream engine exposed to Swift through UniFFI,
  with tests that compare its output with the upstream pipeline.
- **SpektrafilmKit**: image decoding (RAW through `CIRAWFilter`), settings, rendering, export with color
  management, covered by tests on the real engine.
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
- **Not verified yet**: real RAW files from a camera (decoding time, highlights, metadata), drag and drop,
  trackpad gestures, and the Open panel.

## Next, in this order

Decided on 2026-11-19, towards version 1.0 as described in [VISION.md](VISION.md). One branch and one
draft pull request per step.

1. **Defects found by driving the app.** Fixed on 2026-11-19, each with tests and checked again on the
   built app: several files opened at once, the keyboard and accessibility steps of `ParameterSlider`,
   black and white films printed on a color paper, the export file name, and commands enabled with
   nothing to act on. Still open:
   - There is no undo: Reset Adjustments cannot be taken back (solved with step 5).
   - With a black and white print the yellow and magenta filters stay visible, and the development
     times the black and white profiles carry are not offered.
2. **The interface redrawn** in the visual direction of the vision, as the mockups of 2026-11-20
   settled it: a slider of our own (neutral colors, fill from the neutral point, keyboard and
   accessibility by step), the film as the heading and its list with an emblem per film, collapsible
   sections, the toolbar, the zoom controls under the photo. Snapshots and `KeyboardCheck` tests with it.
3. **Immediate editing.** Measured on 2026-11-20 (see above). Done: the viewer no longer builds
   mipmaps for every frame; while the settings change the preview is rendered at 1024 px, then at the
   size the viewer needs; `PreviewBudgetTests` keeps a preview update under 50 ms at 1024 px and under
   200 ms at 2048 px on a Mac's GPU (on CI, whose virtual GPU is several times slower, it checks only
   that the lighter preview costs much less than the standard one). Still open, in this order:
   - Render what the viewer shows: a fitted photo in a large window needs about 2400 to 3000 px, not
     the full resolution (a second or more at 24 MP).
   - Let a lighter render overtake a full-resolution one in progress: today the next update waits for
     it to finish.
   - No round trip of the pixels through main memory (see "GPU texture sharing" and "100% view" below).
   - The 7.5 ms of recalibration on exposure, filters and preflash are inside the upstream engine: to
     propose upstream, not to patch here.
   - Not measured yet: what SwiftUI redraws while a slider moves (needs Instruments on the app).
4. **White balance** (temperature and tint) from the RAW decoder.
5. **Edits that persist**, with undo and redo.
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
12. **Version 1.0**: the icon, the name, the notarized release.

After 1.0, in an order still to decide: the Photos integration, more of the engine's parameters behind
an "advanced" section.

Defects found on real RAW files go to step 1.

## Open questions

- **Export precision.** Upstream offers an f64 CPU build for exact parity with Python. f32 and f64 builds
  cannot share one static library, so if the difference turns out to be visible the f64 engine would ship
  as a separate helper (an XPC service) used only for export.
- **Photos extension.** As far as we know, Photos hands editing extensions a rendered image rather than
  the RAW original, which would lower the quality compared with the app (the app can read originals from
  the library through PhotoKit). To verify first thing in phase 3.
- **GPU texture sharing.** Previews currently travel GPU → CPU → GPU. If that becomes the bottleneck, wgpu
  can render into an `IOSurface` shared with the viewer's layer.
- **100% view.** Zooming in renders the whole photo at full resolution. The engine has no
  region-of-interest rendering yet; rendering only the visible area would make large photos much faster.
- **RAW highlights.** `CIRAWFilter` is used with its tone curve off. Whether its extended dynamic range
  setting should be raised to keep more highlight detail needs a look at real files.
- **The app's name.** The app is called spektrafilm, the name of the upstream project it builds on.
  Whether it keeps that name or takes one of its own is undecided.
- **Distribution.** The app is signed to run locally, and CI packages it as an artifact. Giving it to other
  people needs a Developer ID signature and notarization, which need an Apple developer account. The Mac
  App Store is excluded ([ADR 0001](adr/0001-reuse-the-rust-engine.md)).
- **XcodeGen projects in swift-harness.** The plugin reads build settings from a committed project file;
  here the project is generated, so the signing settings were moved to an `.xcconfig`.
