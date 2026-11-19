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
- **Not verified yet**: real RAW files from a camera (decoding time, highlights, metadata), drag and drop,
  trackpad gestures, and the Open panel.

## Next, in this order

Decided on 2026-11-19, towards version 1.0 as described in [VISION.md](VISION.md). One branch and one
draft pull request per step.

1. **Defects found by driving the app** (each with a test that fails on the old code):
   - Several files opened at once (Finder, `open`) add only the first to the strip; one at a time works.
   - `ParameterSlider`: no keyboard focus unless the system's "Keyboard navigation" is on, so the arrow
     keys and Delete do nothing; the accessibility increment moves a tenth of the range (1 EV for
     exposure) instead of one step.
   - A black and white negative film keeps the color paper and comes out orange.
   - The export file name carries the film's internal id (`kodak_portra_400`), not its name.
   - The quality slider of the export sheet has no accessibility label.
   - There is no undo: Reset Adjustments cannot be taken back (solved with step 5).
   - With no photo open, the zoom and previous/next commands are still enabled.
2. **The inspector redrawn** in the visual direction of the vision: a slider of our own (neutral colors,
   fill from the neutral point, keyboard and accessibility by step), the film as the heading, spacing and
   type. Snapshots and `KeyboardCheck` tests with it.
3. **Immediate editing.** Measure where the 0.1 s of a preview update goes, then remove it: a lighter
   preview while a control moves, rendering only what the viewer shows, and no round trip of the pixels
   through main memory (see "GPU texture sharing" and "100% view" below). A performance budget test keeps
   the result.
4. **White balance** (temperature and tint) from the RAW decoder.
5. **Edits that persist**, with undo and redo.
6. **Looks**: save and apply, copy between photos, export several photos, adaptive application.
7. **Crop and straighten.**
8. **Camera and lens corrections**, after the open question on their source.
9. **Workflows from the Finder**: Shortcuts actions that develop the photos they receive with a look and
   return the files, so the shortcut saves them (for example in a subfolder beside the originals) and can
   run as a Finder Quick Action. Needs steps 6 and 8.
10. **The rest of the harness**, spread over the steps above where it helps: a UI test target
   (`AccessibilityAudit`, `LayoutAudit`, `FocusOrder`) that makes the checks of step 1 permanent, then
   `SCHEME_HAS_TESTS=1` in `scripts/verify.sh`; pane measurements for `docs/LAYOUT_CONTRACT.md`;
   `/swift-harness:product-map` and `/swift-harness:audit`.
11. **Version 1.0**: the icon, the name, the notarized release.

After 1.0, in an order still to decide: collections, the Photos integration, more of the engine's
parameters behind an "advanced" section.

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
