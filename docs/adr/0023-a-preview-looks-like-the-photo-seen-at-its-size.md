# ADR-0023: A preview looks like the developed photo seen at its size

- Status: Accepted
- Date: 2026-11-25

## Context

The app develops a preview from the photo decoded at the preview's size
([ADR 0007](0007-decode-each-preview-at-its-size.md)). The engine sizes grain and halation from the
film format, so most of the look follows the size by itself. Three lengths do not: the grain's blur
(`film_render.grain.blur`, 0.65), the scan's sharpening (`scanner.unsharp_mask`, radius 0.7, strength
0.7) and the scan's lens blur (`scanner.lens_blur`, off by default) are given in pixels. They weigh as
much on a preview of 2048 pixels as on the photo of 6144, where they mostly vanish once the photo is
seen at 2048.

Measured on 2026-11-24 (`PreviewFidelityTests`): a preview shown pixel for pixel had about two thirds
of the grain of the export seen at its size (0.66 at 2048 px, 0.62 at 1024 px), and its sharpening
changed it 3.0 and 5.7 times as much. A fitted photo looked smoother in its grain and crisper than
the file it exports. The user chose on 2026-11-25 to change it ("parti con la 2 e poi la 1").

## Decision

- **A render smaller than the photo is told the photo's long side** (`FilmRenderer.render(…,
  photoLongSide:)`), and the three lengths in pixels are changed for it in the engine's patch
  (`DevelopSettings.enginePatchJSON(pixelScale:)`, `PixelScaling`). The preview and the strip's
  thumbnails pass it; an export, at the photo's own size, is developed exactly as before.
- **The grain's blur** is the one that takes as much from the grain as the photo's blur still takes
  once its pixels are averaged into the preview's: computed with the engine's own kernel, which blurs
  the grain only above 0.4 pixels. At a third of the photo's size 0.65 becomes 0.43; scaled by the
  size it would be 0.22, which the engine skips, and the preview had 1.3 times the grain.
- **The sharpening's strength follows the size, its radius stays**: a radius scaled down falls under
  half a pixel, where the engine's kernel no longer sharpens.
- **The lens blur of the scan** is scaled by the size, as a length.
- **The glare's blur is left as it is**: it softens a noise drawn per pixel, the same at every size.

## Alternatives considered

| Option | Why not |
|---|---|
| Leave it, as before | A fitted photo is not what the export looks like at that size |
| Scale every length by the size | Measured: the grain 1.33 times the export's at 2048 px, the sharpening gone (0.002): the engine's kernels do not draw a fraction of a pixel |
| Values measured for each preview size | Nothing for a blur or a strength the user changes, nor for a size not measured |
| Develop the preview at the photo's size and scale the result | What ADR 0007 left: seconds for a preview |

## Consequences

- Measured on 2026-11-25 (Apple M5, GPU; the CPU within 0.01): the grain 1.03 of the export's at
  2048 px and 0.98 at 1024 px, 1.03 for the standard preview seen at half its size; the sharpening
  1.24 and 1.09 times. The halation does not change (1.00 and 0.87).
- Every preview looks a little different from before: grainier, less crisp, as its export.
- The film look stays the engine's: the export is the engine's render with the user's parameters,
  and the bridge still passes the parameters it is given. Only a render that stands for a larger
  photo is given other values, for what the engine measures in pixels.
- A new parameter the engine takes in pixels needs its rule here, or a preview differs again;
  `PreviewFidelityTests` catches it for the grain and the sharpening.
