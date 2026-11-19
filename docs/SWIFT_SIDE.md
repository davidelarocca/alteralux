# The Swift side

What each Swift module does and how the app works at run time.
Hub: [ARCHITECTURE.md](ARCHITECTURE.md).

### `SpektrafilmKit` (Swift package)

- **`SpektrafilmEngine`**: the generated UniFFI bindings plus the compiled
  engine as an XCFramework. Nothing else.
- **`SpektrafilmKit`**: what an app needs, without any UI.
  - `ImageLoader` decodes a file to scene-linear Rec. 2020 float pixels. RAW
    files go through `CIRAWFilter` with tone curve, local tone mapping, gamut
    mapping and sharpening turned off; other formats go through ImageIO. It
    also provides the system's default rendering of a file, used for
    thumbnails and for the before/after comparison.
  - `DevelopSettings` is the app's model of an edit (`Codable`). It converts to
    the engine's JSON patch; tests check that the engine accepts it and that
    each value lands on the intended parameter.
  - `FilmRenderer` runs renders on its own queue, off Swift's cooperative
    thread pool, and wraps the result in a `CGImage` tagged linear sRGB.
  - `ImageExporter` writes JPEG, 10-bit HEIC, 16-bit TIFF and PNG through
    Core Image, converting to sRGB or Display P3 and embedding the profile,
    with the original's camera metadata.

The tests of the package run the real engine: they check row order and channel
order end to end, the bit depth and profile of exported files, and the
parameter mapping.

- **`SpektrafilmUI`**: the app model and the screens, as a package target so
  they build and test with `swift test`, outside the sandboxed app.

Its tests (`SpektrafilmUITests`) also draw in real windows, with the helpers
copied from the swift-harness templates (`LayoutContract.swift`,
`Screenshot.swift`, `Snapshot.swift`, kept as shipped):

- the layout contract of the main window (`docs/LAYOUT_CONTRACT.md`);
- snapshots of the shared components, compared with the approved images in
  `snapshots/` (pinned to the macOS version and display scale they were made
  on; elsewhere they are reported as not compared);
- screenshots of the main window, empty and with a developed photo, saved to
  `.build/swift-harness/screenshots/` for review and never compared.

These suites are nested in `WindowedTests`, which runs them one at a time.

### `DesignSystem` (Swift package)

Tokens (`Spacing`, `Radius`, `Typography`, `Motion`, semantic colors) and the
shared components. The only place for raw visual values: see
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) and [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md).

### The app (`apple/Spektrafilm`, `SpektrafilmUI`)

A single-window SwiftUI app. The app target is a shell: the `@main` scene, the
resources, the entitlements. `AppModel` (`@Observable`, main actor) owns the
open photos, the settings of the selected one and its preview.

- **Rendering loop.** A settings change requests a render. Requests made while
  a render is running collapse into one follow-up render with the latest
  settings, so dragging a slider never queues stale frames.
- **Preview resolution.** The preview is rendered at 2048 px on the long side
  while the whole photo is in view, and at full resolution once the viewer
  shows more pixels than that. The viewer's zoom is measured against the full
  photo, so swapping previews does not move the picture.
- **Viewer.** An `NSScrollView` (pinch, smart zoom, scroll) showing the
  `CGImage` through a layer. Core Animation color-manages it for the display.
- **Memory.** Only the selected photo's decoded pixels are kept; the strip
  holds small thumbnails.
- **Sandbox.** Access to opened files is kept for as long as they are in the
  strip, so their metadata can be copied at export time.

The Xcode project is generated from `apple/project.yml` and is not committed.
Code signing and hardened runtime settings live in
`apple/Spektrafilm/Signing.xcconfig`, a tracked file.
