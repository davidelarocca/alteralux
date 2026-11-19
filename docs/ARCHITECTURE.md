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

The Swift app will wrap the parameters it exposes in typed `Codable` structs
that encode to this JSON.

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
  app's Metal view.
