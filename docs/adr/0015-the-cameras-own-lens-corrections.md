# ADR-0015: The corrections the camera records, before lensfun's profiles

- Status: Accepted
- Date: 2026-11-21

## Context

[ADR 0011](0011-recipes-adapt-to-each-photo.md) corrects the lens with Apple's RAW decoder where it
knows it, [ADR 0012](0012-lens-profiles-from-lensfun.md) with lensfun's profiles otherwise. Recent
mirrorless cameras also write, in every RAW, the corrections for the lens on them at the moment of
the shot (distortion, colored fringes, vignetting), whoever made the lens, as long as it talks to the
camera. The user asked for them on 2026-11-21.

Measured on 2026-11-21 on the user's own RAWs (numbers only): 920 Sony files, every one carrying them.
A ZV-E10 with Viltrox 56mm and 25mm lenses, about 390 files, was corrected by nobody: Apple's decoder
does not know these lenses, nor does lensfun. A ZV-E10M2 with a Sigma 56mm was corrected by lensfun;
a ZV-1 by Apple's decoder.

What the numbers mean is not documented by Sony. darktable reads them (from a reverse engineering by
Freddie Witherden), in two versions that differ on the vignetting: its first squares the light kept,
its second does not. On the user's Sigma 56mm at f/1.4, the camera's data give the corners -1.6 EV
squared and -0.8 EV not, and lensfun's own measurement of the lens -2.0 EV: the squared reading is the
one that agrees.

## Decision

- Sony's three tags (`0x7032` vignetting, `0x7035` chromatic aberration, `0x7037` distortion) are read
  from the first directory under the main one of an ARW, with a small TIFF reader
  (`SonyLensData`, `TIFFReader`): ImageIO does not give them. The meaning is darktable's: knots at
  `(i + 0.5) / (n - 1)` of the half diagonal, straight lines between them, distortion `1 + d / 2^14`,
  fringes `1 + c / 2^21` over green's, light kept `(2^(0.5 - 2^(v / 2^13 - 1)))^2`.
- The curves are applied as they are by a second Core Image kernel beside lensfun's (`LensWarp`),
  in the same place: on the decoder's scene-linear output, before the frame and before the engine.
  The picture is zoomed so it fills the frame, as with lensfun. A Swift reference of every formula
  (`CameraLensCorrection`) is what the tests compare the kernel with.
- The order is: Apple's decoder where it knows the lens, then what the camera recorded, then
  lensfun. The user chose it on 2026-11-21: the camera's data are the maker's own, for that focal
  length, aperture and distance. Photos of the Sigma 56mm already developed with lensfun change
  slightly.
- The inspector says which one corrects the photo: "Camera's own correction" or "Lensfun profile",
  with the lens's name. The switch is the same as for the other two.

## Alternatives considered

| Option | Why not |
|---|---|
| Fitting the curves into lensfun's polynomials, to reuse its kernel | Measured on the user's files: up to 8.5 pixels off on the Viltrox 25mm's distortion |
| darktable's second reading of the vignetting, not squared | Half the darkening lensfun measured on the same lens |
| lensfun first, the camera's data only where it knows nothing | Leaves a general profile where the maker's own numbers for the shot are there |
| Reading the tags with exiv2 or libraw | A C++ dependency for three tags of a TIFF |

## Consequences

- Every Sony RAW whose lens talks to the camera is corrected, the user's Viltrox lenses among them.
- The other makers that record corrections (Fujifilm, OM/Olympus, Panasonic, Nikon Z, Canon RF, and DNG
  files' own opcodes) are not read yet: each is a reader of its own, to add when a photo needs it.
- The reading of the numbers is a reverse engineering: if a Sony photo looks wrong, the formulas in
  `SonyLensData` are where to look.
