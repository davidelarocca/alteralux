# ADR-0011: Recipes that adapt to each photo, and the lens corrected by the RAW decoder

- Status: Accepted
- Date: 2026-11-21

## Context

Workflows from the Finder develop photos nobody looks at one by one, with a recipe. The vision asks
that they adapt to each photo: a starting exposure and a starting temperature of its own, the
recipe's look on top, and the lens corrected. The user asked on 2026-11-21 for workflows, adaptive
recipes and lens corrections together, so a workflow adapts and corrects the lens from the first day.

[ADR 0009](0009-recipes-are-looks-kept-by-the-app.md) keeps the white balance out of recipes: it
belongs to the light of each photo. The engine already meters each photo when its automatic meter is
on. White balance is chosen in Apple's RAW decoder, before the engine
([ADR 0007](0007-decode-each-preview-at-its-size.md)), and the engine works linear in, linear out
([ADR 0002](0002-linear-in-linear-out.md)).

`CIRAWFilter` offers a lens correction (`isLensCorrectionSupported`, `isLensCorrectionEnabled`) for the
cameras and lenses it knows, and nothing else documented. Before this change the app never set it, so
each photo had what the decoder chose on its own.

## Decision

- A recipe has one more property, **adapts to each photo**. A recipe that adapts, given to a photo,
  turns its meter on and its white balance to automatic, unless the photo's white balance was chosen
  by hand. What a recipe holds does not change: still no white balance.
- **Automatic white balance** is a photo's setting (`DevelopSettings.autoWhiteBalance`), with its own
  switch in the inspector. A white balance chosen by hand wins over it; moving a slider while it is on
  keeps where the sliders stood and turns it off.
- The automatic white balance is measured in `PhotoDecoder`, once per photo: the RAW decoded at 256
  pixels with the camera's white balance, a "shades of gray" mean (power 6) over the pixels neither
  clipped nor very dark, the decoder's neutral moved by the color found, twice. The camera's white
  balance is kept unless the one found is more than 25 mired or 15 of tint away; then the photo moves
  60% of the way. Fewer than 20% of usable pixels keeps the camera's. Files that are not RAW have none.
- **Lens correction** is a photo's setting too (`DevelopSettings.lensCorrection`), on for new photos,
  applied through `CIRAWFilter` where it is supported. Adjustments saved before it existed read as
  "not chosen" (`nil`) and keep what the decoder did on its own, so a photo already developed does not
  change, crop included, until the switch is touched. Recipes and pasted adjustments leave a photo's
  lens correction as it is, as they leave its white balance and its frame.

## Alternatives considered

| Option | Why not |
|---|---|
| The automatic white balance as part of the recipe's look | It would decide each photo's light from a recipe, against ADR 0009, and turn it off on photos that had it |
| `neutralLocation` of `CIRAWFilter`, or Core Image's auto adjustments | The first needs a neutral point chosen in the photo; the second has no white balance of its own (`CIFaceBalance` only with faces) |
| Gray world or max-RGB | Gray world follows a large colored area; max-RGB a clipped highlight. Shades of gray sits between them for the same cost |
| The automatic white balance always used as found | The camera's is usually close, and a measurement can be fooled by a scene colored on its own: a threshold and part of the way keep the mistakes small |
| Lens correction on for every photo, old ones included | A photo already developed and cropped could change under the user's eyes |

## Consequences

- A workflow can give each photo its own starting exposure and white balance, then the recipe's look.
- The thresholds (25 mired, 15 tint, 60%) are a starting point measured on test RAWs only: they are to
  be judged on real photos.
- The lens correction covers what Apple's decoder knows. Lenses it does not know need profiles of our
  own: lensfun's database, shipped unmodified as a separate file (the next step of the roadmap).
