# Architecture

## Why this shape

The spectral film model is large and subtle: about 10 000 lines of Python in
[spektrafilm](https://github.com/andreavolpato/spektrafilm), ported to about
27 000 lines of Rust in [spektrafilm-rs](https://github.com/turbasvin/spektrafilm-rs).
The Rust port is verified against the Python reference (identical results at
f64 precision on the core chain, according to its README) and already runs its
preview on Metal through wgpu. Rewriting it in Swift
would mean redoing that work and that verification. This project reuses the
Rust engine unchanged and puts a native macOS app around it.

```
┌──────────────────────────── macOS app (Swift) ─────────────────────────────┐
│ SwiftUI windows · Metal preview · Core Image RAW · ColorSync · extensions  │
└──────────────────────────────────────┬─────────────────────────────────────┘
                                       │ SpektrafilmKit (Swift package)
                                       │   generated UniFFI bindings
┌──────────────────────────────────────┴─────────────────────────────────────┐
│ spektrafilm-ffi (Rust): Engine · SourceImage · RenderedImage · params JSON  │
└──────────────────────────────────────┬─────────────────────────────────────┘
                                       │ plain Rust calls
┌──────────────────────────────────────┴─────────────────────────────────────┐
│ spektrafilm-rs (git submodule, pinned): core · model · math · gpu          │
│   CPU (Accelerate BLAS + rayon) or GPU (wgpu → Metal)                       │
└────────────────────────────────────────────────────────────────────────────┘
```

The upstream engine is a **git submodule pinned to a commit**. We never patch
it: anything macOS-specific lives in this repository. Updating the engine means
moving the submodule pointer and re-running the tests.

## The bridge contract (`engine/crates/spektrafilm-ffi`)

### Linear in, linear out

The app hands the engine **scene-linear** RGB and gets back **display-linear**
RGB in `[0, 1]`. The bridge forces `input_cctf_decoding = false` and
`output_cctf_encoding = false` on every render, so the engine never applies a
transfer function. Everything around it is done natively:

- **Input.** `CIRAWFilter` decodes RAW files (including Apple ProRAW) to linear
  Rec. 2020. ImageIO handles TIFF and EXR.
- **Output.** The result is tagged with the matching linear `CGColorSpace`.
  ColorSync then converts it for the display (Display P3 on Apple screens) and
  for each export format.

Output color space: `Srgb` reproduces the reference look exactly, including the
engine's perceptual output gamut compression, which upstream only implements for
sRGB. Wider output spaces keep more saturated colors but skip that compression.
The app defaults to sRGB.

### Parameters as JSON

The engine has well over a hundred parameters (`RuntimeParams`). Instead of
mirroring each one in the FFI, the bridge accepts a **partial JSON tree** that
is deep-merged over the defaults:

```json
{ "camera": { "exposure_compensation_ev": 0.7 },
  "enlarger": { "y_filter_shift": -3 } }
```

- Unknown keys are **errors** (with their path, e.g. `camera.exposur`), so a
  typo or an upstream rename never fails silently.
- `null` sets an optional value to "none" (it does not delete the key).
- `Engine.defaultParamsJson()` returns the full tree: it documents every
  tunable and is the starting point for presets.

The Swift side wraps the parameters the app exposes in `DevelopSettings`, which
produces this JSON.

### Pipeline cache

Building a pipeline (spectral LUTs, enlarger calibration) is expensive;
running it is cheap by comparison. The engine keeps the last calibrated
pipeline and reuses it when only non-calibration parameters change. This is
the common case: exposure, grain, halation and scanner settings. The cache key
mirrors the upstream GUI's `preview_pipeline_cache_key`. A test checks that a
warm engine and a fresh one give identical pixels across a sequence of edits.

### Previews

`RenderRequest.maxDimension` downsizes the source with Catmull-Rom (cached per
source image) before rendering, as the upstream GUI does. The simulation scales
grain and halation from the physical film format, so a preview looks like the
full render.

### Pixels and safety

- Pixels cross the boundary as bytes (`Data` in Swift): RGBA half float for
  previews (`rgba16Float` textures) or RGBA float for export.
- Non-finite input values are zeroed.
- Every exported call catches panics and returns `EngineError.internal`
  instead of unwinding into Swift.
- `Engine` is thread-safe; renders can overlap.

## The Swift side

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

### The app (`apple/Spektrafilm`)

A single-window SwiftUI app. `AppModel` (`@Observable`, main actor) owns the
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

## Roadmap notes

- **Export precision.** Upstream offers an f64 CPU build for exact parity with
  Python. f32 and f64 builds cannot share one static library, so if the
  difference turns out to be visible we will ship the f64 engine as a separate
  helper (an XPC service) used only for export.
- **Photos extension.** As far as we know, Photos hands editing extensions a
  rendered image rather than the RAW original, which would lower the quality
  compared with the app (the app can read originals from the library through
  PhotoKit). To verify first thing in phase 3.
- **GPU texture sharing.** Previews currently travel GPU → CPU → GPU. If that
  becomes the bottleneck, wgpu can render into an `IOSurface` shared with the
  viewer's layer.
- **100% view.** Zooming in renders the whole photo at full resolution. The
  engine has no region-of-interest rendering yet; rendering only the visible
  area would make large photos much faster at 100%.
