# ADR-0007: Decode each preview at its size, with Core Image

- Status: Accepted
- Date: 2026-11-20

## Context

White balance belongs to the RAW decoder: it is chosen before the camera's data becomes RGB, so the app
has to decode the photo again whenever the temperature or the tint changes.

Until now the app decoded the whole photo once, handed it to the engine, and let the engine reduce it
for each preview. Measured on an Apple M5 with a 24 MP Sony RAW:

- decoding the whole photo and handing it to the engine takes 1.15 s (about 0.3 s in the decoder, the
  rest is reading 384 MB back from the GPU and copying them into the engine);
- the engine then scales it for a preview in 0.25 to 0.37 s, once per size;
- so the first picture came 1.6 s after opening, and a white balance change would cost more than a
  second: nothing a slider can follow.

The same decoder, kept alive between calls and asked for a smaller image (`CIRAWFilter.scaleFactor`),
gives a 1024 px preview with a new white balance in 65 ms, a 2048 px one in 70 to 85 ms and a 3072 px
one in 100 ms. A new decoder for every call costs 200 ms even at 1024 px.

## Decision

The app keeps one `PhotoDecoder` (AlteraluxKit) for the selected photo. It holds the `CIRAWFilter`, or
the `CIImage` of a file that is not a RAW, and decodes the photo on request at a given size and, for a
RAW, with a given white balance.

Every source the engine receives from the app is already at the size to render: the app model asks the
decoder for the size `PreviewSize` picks and renders it with `maxDimension` 0. The whole photo is
decoded for the 100% view and for export, ahead of need once the preview is on screen. `PhotoSources`
(AlteraluxUI) keeps what was decoded for the current white balance: three reduced sizes and the whole
photo.

White balance is two optional values in `DevelopSettings`, where `nil` means "as the camera recorded".
It never reaches the engine: the bridge still moves pixels and parameters without changing them.

Only a RAW's white balance can be chosen. Other files show the controls disabled.

## Alternatives considered

| Option | Why not |
|---|---|
| Decode the whole photo again at every change and let the engine scale it | More than a second per change: against the principle that editing is immediate |
| Reduced decodes only while a white balance slider moves, the old path otherwise | Two ways to make a preview, with two scaling filters: the picture would shift slightly when the hand lets go |
| Apply white balance after decoding, as a chromatic adaptation on RGB | Less faithful than the decoder's own on RAW data, and it is the one thing a RAW is for |
| White balance on every format, by chromatic adaptation | Asked and declined for now (2026-11-20): only RAW files, as the roadmap says |

## Consequences

- Opening a RAW shows its first picture in 0.4 to 0.6 s instead of 1.6 s, and a temperature drag shows
  a frame about every 90 ms (other sliders: every 30 ms).
- A preview is scaled by Core Image (the RAW decoder's own scaling, or Lanczos for other files), not by
  the engine's Catmull-Rom. Export and the 100% view are not scaled at all, so the developed file is
  unchanged. The engine's `maxDimension` and its cache of scaled sizes stay in the bridge, tested, and
  unused by the app.
- The decoder runs one decode at a time. Decoding the whole photo keeps it busy for some tenths of a
  second: that is why it is done ahead only after a quiet second, and dropped when the white balance
  changes.
- The first zoom to 100% waits for the whole photo if it was not decoded yet: about 1.2 s more.
- Tests need a RAW file. `TestDNG` writes a small linear DNG that Apple's decoder opens; a copy is kept
  in `apple/AlteraluxKit/Tests/Fixtures/` for the tests of AlteraluxUI, and a test keeps the two equal.
