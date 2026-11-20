# ADR-0010: Crop and straighten before the engine

- Status: Accepted
- Date: 2026-11-20

## Context

Roadmap step 8 adds crop and straighten. The engine sizes its spatial effects (grain, halation,
diffusion, couplers) from the pixel pitch on the film, which it derives from the picture it receives:
`pixel_size_um = film_format_mm * 1000 / longest side` (`spektrafilm-core/src/stages/filming.rs`).
Whatever reaches the engine is taken as one whole frame of the film format the user chose. The
automatic meter also reads the picture the engine receives.

So where the crop happens decides what the user sees:

- cropped before the engine, the framed picture is a whole frame: the grain keeps its size relative to
  the picture, however tight the crop;
- cropped after the engine, the crop enlarges a piece of a developed frame: the grain grows with the
  crop, as when a piece of a negative is enlarged.

The user chose the first on 2026-11-20: the grain must stay the same size.

The engine has crop parameters of its own (`io.crop`, `io.crop_center`, `io.crop_size`), but its
pipeline does not read them.

## Decision

- Crop and straighten are applied in AlteraluxKit with Core Image, after decoding and white balance and
  before the engine. The engine receives the framed picture and nothing about the crop; `io.crop` stays
  off.
- The crop is stored as a rectangle in coordinates relative to the photo as it is shown upright (0 to 1
  on each side), and the straightening as an angle in degrees. They hold at every decoding size, so
  every preview, the 100% view and the export frame the photo the same way
  ([ADR 0007](0007-decode-each-preview-at-its-size.md)).
- They are kept with the photo's other adjustments, in the photo itself
  ([ADR 0008](0008-keep-edits-in-the-photo.md)), and are left out of the patch sent to the engine.
- Like the white balance, they belong to one photo: a recipe never holds them and pasting adjustments
  does not carry them ([ADR 0009](0009-recipes-are-looks-kept-by-the-app.md)).
- While the crop is being changed, the viewer shows the whole photo developed, with the frame drawn
  over it; the framed picture is developed again when the change ends.

## Alternatives considered

| Option | Why not |
|---|---|
| Crop after the engine | The grain, the halation and the glow grow with the crop: a tight crop of a 35 mm frame looks like a much smaller film. The user wants the film format to describe the finished picture. It also spends the engine's time on pixels that are thrown away |
| Crop before the engine and shrink the film format by the crop, so it looks as if cropped after | The same look as cropping after, at the cost of the framed pixels only; turned down with it |
| The engine's own `io.crop` | Its pipeline does not read it, and the engine must not be patched here |
| Crop and angle in a recipe, or carried by pasting | A frame chosen for one photo means nothing for another; same reason as the white balance in ADR 0009 |

## Consequences

- The film format means the finished picture: to get more grain on a tight crop, the user picks a
  smaller format.
- The automatic meter reads the framed picture, so a crop can change the exposure it suggests.
- A tight crop is exported from fewer pixels, so its export is faster.
- Thumbnails in the library and the strip show the framed picture.
- The bridge and the engine are untouched: the comparison with the upstream pipeline keeps holding.
