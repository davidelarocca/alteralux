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
  settings still. A zoom is not held back. The strip's thumbnail follows the
  settled preview only. The photo is scaled for the 1024 px preview as soon
  as it is on screen (`FilmRenderer.preparePreview`), so the first move does
  not wait.
- **Viewer.** An `NSScrollView` (pinch, smart zoom, scroll) showing the
  `CGImage` through a layer. Core Animation color-manages it for the display.
  The layer reduces the image through mipmaps only below half size
  (`ImageScrollView.needsMipmaps`): see `docs/PITFALLS.md`.
- **Memory.** Only the selected photo's decoded pixels are kept; the strip
  holds small thumbnails.
- **Sandbox.** Access to opened files is kept for as long as they are in the
  strip, so their metadata can be copied at export time.

The Xcode project is generated from `apple/project.yml` and is not committed.
Code signing and hardened runtime settings live in
`apple/Alteralux/Signing.xcconfig`, a tracked file.
