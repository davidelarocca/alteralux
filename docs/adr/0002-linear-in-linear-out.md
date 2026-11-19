# ADR-0002: Keep the engine linear in, linear out

- Status: Accepted
- Date: 2026-11-19

## Context

Color can be managed in two places: inside the engine (it has input decoding and output encoding flags)
or by macOS (Core Image, ColorSync, Core Animation). Doing some of it in each place makes it easy to
apply a transfer function twice or to tag pixels with the wrong color space.

## Decision

The bridge forces `input_cctf_decoding` and `output_cctf_encoding` off on every render. The app hands the
engine scene-linear Rec. 2020 pixels and gets display-linear pixels back, which it tags with the matching
linear `CGColorSpace`. Every transfer function and gamut conversion, for the display and for each export
format, is done by macOS.

The output space is sRGB by default: the engine implements its perceptual output gamut compression only
for sRGB, and that is the reference look.

## Alternatives considered

| Option | Why not |
|---|---|
| Let the engine encode sRGB | The preview and each export format would need their own conversions anyway, from encoded data |
| Output Rec. 2020 by default | Keeps wider colors but skips the engine's gamut compression, so the look departs from the reference |

## Consequences

- One place to look for color bugs. Tests check row order, channel order, bit depth and embedded profile
  of exported files.
- A wide-gamut output mode is possible later as an explicit option.
