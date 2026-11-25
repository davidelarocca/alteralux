# ADR-0022: The automatic exposure and white balance read the photo as it was shot

- Status: Accepted
- Date: 2026-11-25

## Context

With the exposure on "Auto" ([ADR 0020](0020-automatic-means-automatic.md)) the meter read the photo
as the adjustments decode it: with the white balance chosen, the lens corrected or not, the frame
cut, the RAW decoder's highlight recovery and noise reduction. So cutting a bright window out of the
frame, or warming the photo, changed the exposure of everything else, and turning "Auto" off and on
again gave another exposure than the first time. Only what comes after the meter never moved it: the
highlights and shadows ([ADR 0019](0019-highlights-and-shadows-before-the-film.md)), the film, the
print, the scan.

The automatic white balance was already measured on the whole RAW with the camera's white balance,
once for each photo opened, but with the decoder as the last decode had left it: with the highlight
recovery, the noise reduction and the lens correction of the adjustments, when it was turned on after
them.

The user, on 2026-11-25, after using it:

> io vorrei che il calcolo e il ricalcolo dell'esposizione e della temperatura automatica venga fatto
> sempre e solo sulla base della foto originale in partenza, senza tenere conto delle altre modifiche.

## Decision

- **The meter reads the photo as it was shot**: whole, with the white balance the camera recorded,
  the lens corrected as the app corrects it when nothing was chosen, the RAW decoder's own choices.
  No adjustment changes the reading but the metering method, which is the meter's own. It is still
  the engine's meter that reads it, through the bridge, on the photo decoded small.
- So, with the exposure automatic, **the decoder always puts the meter's exposure into the pixels**
  and the film is exposed with the meter off, as ADR 0019 does it for the highlights and shadows:
  the engine's own meter would read the picture it is given, cut and balanced as it is. Previews,
  thumbnails and exported files share that one reading.
- **The automatic white balance is measured with the decoder put back to the photo's own choices**,
  on the whole RAW with the camera's white balance, as before.
- The adjustments are stored as before: nothing is added to a photo or to a recipe. A recipe on "Auto"
  gives each photo the exposure and the white balance of that photo as it was shot.

## Alternatives considered

| Option | Why not |
|---|---|
| The meter follows the frame and the white balance, as it did | What the user turned down: a control far from the exposure changes it |
| The whole frame, but with the white balance chosen | Still an adjustment that moves the exposure; the user asked for the original alone |
| The first reading kept beside the adjustments | A number to keep in step with the metering method and the photo; reading the original again gives it anyway |
| The reading handed to the engine as exposure compensation | The lab's compensation at the print would undo it (ADR 0019) |

## Consequences

- A photo cut down to a part much brighter or darker than the whole keeps the exposure of the whole:
  the compensation in the meter's group, or the exposure by hand, corrects it.
- A photo already adjusted with a frame or a white balance of its own, and the exposure automatic,
  changes a little in brightness. Nobody uses the app yet.
- ADR 0019's "with both sliders at zero nothing of this runs" no longer holds with the exposure
  automatic: the photo is then always metered on a copy 256 pixels wide, the size the engine's meter
  reduces every picture to, and decoded through the kernel that puts the exposure into the pixels.
  A change of the metering method decodes the photo again; the exposure compensation does not, while
  the highlights and shadows are at zero. With the exposure by hand and both at zero nothing runs.
- The reading on the reduced copy and the engine's own on a larger picture differ a little, as ADR 0019
  noted. Measured on a 24 megapixel RAW (Sony A7 III): 0.005 of a stop against a preview of 1024 or
  2048 pixels, 0.015 against the whole photo. On the same RAW the reading followed a white balance
  moved from 4400 K to 7500 K by 0.22 of a stop, and a frame on its top left quarter by 0.73. The
  first reading takes 0.15 s, once for each photo opened; a preview decodes in the same time with
  the exposure in its pixels as without.
- The automatic white balance hardly moved with the decoder's other choices (0.01 K on that RAW):
  measuring it on the decoder's own makes it the same whenever it is asked.
