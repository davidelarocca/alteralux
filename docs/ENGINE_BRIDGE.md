# The engine bridge

How the Rust engine is reused and what the bridge between Rust and Swift guarantees.
Hub: [ARCHITECTURE.md](ARCHITECTURE.md).

## Why reuse the Rust engine

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
                                       │ AlteraluxKit (Swift package)
                                       │   generated UniFFI bindings
┌──────────────────────────────────────┴─────────────────────────────────────┐
│ alteralux-ffi (Rust): Engine · SourceImage · RenderedImage · params JSON  │
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

The bridge reports the upstream engine's version (`engine_version()`, read from
the submodule's manifest when the bridge is built), and the app writes it
beside every photo's adjustments and in every recipe. It is the only trace of
which film model a saved look was made with, so the pointer moves from one
upstream release to the next, not to a commit between two that still carries
the earlier version.

## The bridge contract (`engine/crates/alteralux-ffi`)

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
the common case: grain, halation, couplers and scanner settings. Moving the
exposure, the print filters or the preflash builds a new pipeline, about 9 ms
on an Apple M5: with `print_exposure_compensation` on, which is the default,
the exposure is part of the calibration. The cache key
mirrors the upstream GUI's `preview_pipeline_cache_key`. A test checks that a
warm engine and a fresh one give identical pixels across a sequence of edits.

### Previews

`RenderRequest.maxDimension` downsizes the source with Catmull-Rom before
rendering, as the upstream GUI does. The source keeps its last three sizes: the
app alternates between a small preview while a control moves and a larger one
when it stops, and scaling a 24 MP photo takes about 250 ms, far more than
rendering the preview. `SourceImage.preparePreview(maxDimension:)` scales ahead
of time. The simulation scales
grain and halation from the physical film format, so a preview looks like the
full render, as far as its pixels can show it. Measured on 2026-11-24 against a
6144 px render seen at the preview's size (`PreviewFidelityTests`): the
halation is within a tenth at 2048 px; the grain of a preview shown pixel for
pixel is about two thirds as strong, at any size, because upstream blurs the
grain by a number of pixels (`grain.blur`, 0.65) and not by a length on the
film, so the blur weighs the same on a preview and vanishes from the full
render once it is seen smaller. The scan's sharpening has its radius in pixels
too: it changes a 2048 px preview three times as much as the full render seen
at that size.

Since [ADR 0007](adr/0007-decode-each-preview-at-its-size.md) the app no longer
uses this: it hands the engine a source already decoded at the size of the
preview and asks for `maxDimension` 0. The scaling and its cache stay here,
with their tests, for any other caller.

### The meter

`SourceImage.metered_ev(method, input)` returns what the engine's meter reads
for a picture, in stops: the upstream function a render calls when
`camera.auto_exposure` is on. Pixels scaled by two to that power and rendered
with the meter off are the photo the engine would have exposed itself (a test
compares the two). The app uses it to change the scene's light after the meter
has read it ([ADR 0019](adr/0019-highlights-and-shadows-before-the-film.md)),
and to meter the photo as it was shot whatever the frame and the white balance
it is then developed with
([ADR 0022](adr/0022-the-automatic-modes-read-the-photo-as-shot.md)).

### Pixels and safety

- Pixels cross the boundary as bytes (`Data` in Swift): RGBA half float for
  previews (`rgba16Float` textures) or RGBA float for export.
- Non-finite input values are zeroed.
- Every exported call catches panics and returns `EngineError.internal`
  instead of unwinding into Swift.
- `Engine` is thread-safe; renders can overlap.
