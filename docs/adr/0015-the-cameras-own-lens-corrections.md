# ADR-0015: The corrections cameras record, combined with Apple's decoder and lensfun

- Status: Accepted
- Date: 2026-11-21

## Context

[ADR 0011](0011-recipes-adapt-to-each-photo.md) corrects the lens with Apple's RAW decoder where it
knows it, [ADR 0012](0012-lens-profiles-from-lensfun.md) with lensfun's profiles otherwise. Mirrorless
cameras also write, in every RAW, the corrections for the lens on them at the moment of the shot,
whoever made the lens, as long as it talks to the camera. The user asked on 2026-11-21 for all of them
("incorporare tutti i profili possibili, in modo da rendere l'app rilevante per tutti"), vignetting
included.

Measured on 2026-11-21 (numbers only) on the user's 920 Sony RAWs, all carrying them, and on CC0
samples from raw.pixls.us for Fujifilm, Nikon Z, Olympus, Panasonic, Sony, Canon and DNG:

- Apple's decoder corrects the geometry of most recent bodies (`isLensCorrectionSupported`), and of
  Sony only for some lenses: not the user's Viltrox lenses on a ZV-E10, nor an A7 III's lens.
- Where it does, its correction matches our reading of the camera's numbers to a few pixels on a
  6000-pixel photo, for every maker (Nikon 0–4, Olympus 0.3, Panasonic 1–7, Fujifilm 1–5, Sony about
  1): it reads the same numbers.
- Against the sensor's own values, read from uncompressed and Sony-compressed files: Apple's decoder
  lifts Nikon's vignetting itself, with its lens correction on or off; it never lifts Sony's or
  Fujifilm's. DNG files carry theirs as opcodes, which it applies.
- Canon records no coefficients that can be read.

The numbers' meaning is not documented by the makers. darktable and ART (GPLv3, as this app) read
them, from reverse engineering. For Sony they disagree: darktable places the knots at
`(i + 0.5) / (n - 1)` and squares the vignetting in its first version, not in its second; ART places
them at `i / (n - 1)`, squares it, and scales it by 0.7 "empirically determined on my lenses". On the
user's Sigma 56mm at f/1.4, lensfun's own measurement of the lens gives the corners -0.54, -1.03, -1.65
and -2.12 EV at radii 0.5, 0.7, 0.9 and 1; ART's knots squared give -0.50, -0.90, -1.44 and -1.73,
darktable's -0.42, -0.79, -1.30 and -1.58, without the square half of those. On a Sony RX100 VII,
Apple's own distortion correction matches ART's knots to a pixel.

## Decision

- Each maker's numbers are read from the file with a small TIFF reader (`TIFFReader`): Sony's three
  tags of the raw directory (`SonyLensData`), Fujifilm's tables in the RAF's own directory
  (`FujifilmLensData`), Nikon Z's blob in tag `0xC7D5` (`NikonLensData`), Olympus and OM System's
  ImageProcessing tags (`OlympusLensData`), Panasonic's `0x0119` (`PanasonicLensData`). Each reading
  is documented in its file, after darktable and ART; for Sony, ART's knots and the square, without
  the 0.7.
- Every reading becomes radial curves (`CameraLensData`): for each channel the factor from the
  corrected radius to the shot one, and the light kept by the shot radius.
- The order (`CameraLensCorrection.combining`): the geometry by Apple's decoder where it knows the
  lens, then by the camera, then by lensfun; the vignetting by the camera, except where Apple's
  decoder lifts it itself (Nikon), then by lensfun when Apple's decoder leaves the photo alone. Where
  Apple's decoder corrects the geometry, the camera's vignetting is read at the radius the camera's
  own curve says the pixel came from. The user chose the camera before lensfun on 2026-11-21.
- One Core Image kernel applies the curves, from a table of 1024 radii (`LensWarp`), on the decoder's
  scene-linear output, before the frame and before the engine, with the picture zoomed to fill the
  frame. lensfun's profile alone keeps its own kernel. Swift references of the formulas are what the
  tests compare the kernel with.
- The inspector says who corrects what: "Camera's own correction", with lensfun's vignetting, lensfun's
  profile with the camera's vignetting, or the vignetting alone after Apple's decoder.

## Alternatives considered

| Option | Why not |
|---|---|
| Fitting the curves into lensfun's polynomials, to reuse its kernel | Measured on the user's files: up to 8.5 pixels off on a Viltrox 25mm |
| darktable's second reading of Sony's vignetting, not squared | Half of what lensfun measured on the same lens |
| ART's 0.7 on Sony's vignetting | Tuned on its author's lenses; a third of lensfun's measurement on the user's |
| Reading DNG opcodes ourselves | Apple's decoder applies them: they would be applied twice |
| Adding lensfun's vignetting where Apple's decoder corrects the geometry | Whether it lifts the vignetting itself was measured only for Sony, Fujifilm and Nikon |
| Reading the tags with exiv2 or LibRaw | A C++ dependency for a few tags of a TIFF |

## Consequences

- Every Sony, Fujifilm, Nikon Z, Olympus and Panasonic RAW whose lens talks to the camera is corrected,
  where Apple's decoder does not know the lens; Sony's and Fujifilm's vignetting is lifted everywhere,
  which Apple's decoder never did. Photos already developed change accordingly.
- Older Sony bodies keep the numbers in an enciphered block, not read. Canon stays with lensfun.
- The readings are reverse engineering: if a photo looks wrong, the reader of its maker is where to
  look. Sony's vignetting is the least certain: to be judged by eye on a plain sky or wall.
