# ADR-0024: The dropper makes the point clicked gray

- Status: Proposed
- Date: 2026-11-26

## Context

The roadmap left open a picker on the photo for the neutral point (step 4). The automatic white balance
([ADR 0020](0020-automatic-means-automatic.md), [ADR 0022](0022-the-automatic-modes-read-the-photo-as-shot.md))
measures the whole photo as it was shot and moves only part of the way; a photographer with a gray card,
a white wall or a cloud in the frame wants that one thing gray. The user chose this work on 2026-11-26.

## Decision

- A **dropper** stands on the White balance title's row, before the "Auto" switch
  (`InspectorSubheading` with an accessory), for RAW photos only, with the switch on or off.
- On, the photo's pointer is a crosshair, a line over the photo says what to click, with Cancel; Escape
  cancels. A click measures the point and puts the dropper away. A point clipped or nearly black changes
  nothing: the line says so and the dropper waits for another point. Another photo, or the crop,
  puts it away; comparing with the original holds it.
- **The point is measured where the user saw it**: in the photo framed, turned and lens-corrected as
  the adjustments have it, decoded at 1024 pixels with the RAW decoder's options of the adjustments; a
  patch of 7 × 7 pixels around it, clipped and very dark pixels left out. The decoder's neutral moves
  by the patch's color until it is gray (at most four rounds), as `AutomaticWhiteBalance` moves it.
  It goes **all the way** to gray, not part of the way as the automatic one does.
- The result is a **white balance chosen by hand**: the automatic white balance is switched off, the
  sliders show the values, and the change is one step of undo. A recipe saved after it holds no white
  balance, as before ([ADR 0009](0009-recipes-are-looks-kept-by-the-app.md)).

## Alternatives considered

| Option | Why not |
|---|---|
| Measure the point on the photo as shot, as ADR 0022 does for the automatic modes | The point would not be where the user clicked once the photo is cropped or turned |
| Measure on the developed preview | Its colors are the film's: the white balance belongs before the film |
| Show the dropper only with "Auto" off | One more step for the case it is made for; picking a point is itself leaving the automatic |
| Keep the dropper on after a click | One click is what is asked almost always; clicking it again is cheap |

## Consequences

- `PhotoDecoder.whiteBalance(neutralAt:settings:)` decodes the photo up to four times at 1024 px:
  tenths of a second on a 24 MP RAW, off the main actor.
- The viewer (`ImageScrollView`) has a picking mode: a click reports a point instead of moving the photo,
  and its double-click zoom is off meanwhile.
- `InspectorSubheading` takes an optional accessory; its other uses are unchanged.
