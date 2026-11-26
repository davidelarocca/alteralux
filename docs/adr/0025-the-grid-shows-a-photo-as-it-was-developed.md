# ADR-0025: The grid shows a photo as it was developed

- Status: Accepted
- Date: 2026-11-26

## Context

The library's grid showed the camera's own preview of every photo, so a developed photo looked the same
there as one never touched: only a small mark told them apart. The roadmap left this open (step 6), and
the user chose it on 2026-11-26.

Measured that day on a 24-megapixel Sony RAW, in a release build: a thumbnail of 320 px takes about
0.23 s to decode and 15 to 25 ms to develop, another film included (the engine recalibrates in about
10 ms). The decoding runs in Core Image, outside the renderer's queue.

## Decision

- A photo **with adjustments** is shown in the grid and in the strip developed with them, at the tile's
  size, framed by its crop: the tile takes the shape of the frame. Until it is made, the tile shows the
  camera's preview; a tile already developed keeps its image while new adjustments are developed.
- A photo **without adjustments** keeps the camera's preview: it has no look of its own yet (opened,
  it takes the film on screen), and the mark keeps meaning what it meant.
- `DevelopedThumbnails` (AlteraluxKit) makes them with the app's one `FilmRenderer`, two at a time, and
  keeps them in memory (256) and on disk (`Caches/Developed`, pruned at launch to 256 MB). A thumbnail
  is known by the file's path, size and date, the adjustments, `FilmModel.version`, its size and a
  revision of its own, to change when what the app does around the engine changes the look.

## Alternatives considered

| Option | Why not |
|---|---|
| Develop every photo, untouched ones with the default film | Thousands of renders for a look the photo does not have; the grid would no longer say which photos were developed |
| A second engine for the thumbnails | The engine's part is some 20 ms of each; a second engine doubles its memory for little |
| Keep the downscaled preview of the photo on screen | Only the photo developed in this session; the strip already does it for that one |

## Consequences

- A folder with many developed photos fills in over a few seconds the first time, then from the disk.
- A new film model, or a change to the app's own processing before or after the engine, redraws them
  all: bump the revision in `DevelopedThumbnails` when the second happens.
- The thumbnail of the photo on screen is still the downscaled preview (`refreshSelectedThumbnail`).
