# Roadmap

What is done, what is being done and what comes next. Keep it current: it is where a new session starts.

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
- **Not verified yet**: interactive behavior on real hardware (zoom and pan, the strip with several
  photos, comparison, export from the interface), real RAW files from a camera, and performance on large
  photos. Start here when working on a Mac.

## Next: on a Mac, with swift-harness

These steps need Xcode or the user's own approval, so they were left for a local session.

1. `scripts/setup-mac.sh` (tools, engine, Xcode project), then run the app from Xcode on real RAW files.
2. Install the plugin (`/plugin install swift-harness@swift-harness`), check `scripts/verify.sh`, then
   `/swift-harness:approve-verify` and `/swift-harness:doctor`.
3. `/swift-harness:approve-security` after reviewing the recorded baseline (sandbox, hardened runtime).
4. Layout: measure what the panes hold (see "Exceptions" in `docs/LAYOUT_CONTRACT.md`), add
   `Screenshot.capture` tests for the main screens and `Snapshot.verify` tests for the components of
   `docs/COMPONENT_REGISTRY.md`, then `/swift-harness:approve-snapshots`.
5. `KeyboardCheck` tests for `ParameterSlider` (arrows, Delete to reset).
6. A UI test target (`AccessibilityAudit`, `LayoutAudit`, `FocusOrder`); then set `SCHEME_HAS_TESTS=1` in
   `scripts/verify.sh`.
7. `/swift-harness:product-map` to fill `docs/PRODUCT_MAP.md`, and `/swift-harness:audit`.

## Next: features

1. White balance (temperature and tint) from the RAW decoder.
2. Presets: save and apply a look; copy adjustments between photos.
3. Edits that persist: remember each photo's adjustments between launches.
4. An app icon.
5. More of the engine's parameters, behind an "advanced" section.
6. Photos editing extension (phase 3).
7. Finder Quick Action and Shortcuts actions for batch processing (phase 4).

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
