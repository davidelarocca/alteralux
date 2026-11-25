# ADR-0019: Highlights and shadows as light, after the meter and before the film

- Status: Accepted
- Date: 2026-11-24

## Context

The user listed what is set before the film: exposure with the meter, white balance, lens correction,
halation, "and later highlights and shadows", and on 2026-11-23 asked for these two in a pull request
of their own. [ADR 0016](0016-develop-in-the-order-of-the-analog-process.md) said that contrast never
goes before the film, which makes it, and turned down a pre-film exposure of the app's own because the
engine's meter would undo it.

The same holds for highlights and shadows. The engine meters the picture it is given and exposes it so
that its mean falls on middle gray. Measured on a test scene (a dim field with a lamp, the meter on
"average"): with the lamp dimmed before the engine, the meter finds the scene darker and exposes all
of it more; the field, which was not touched, comes out twice as bright (0.036 to 0.073 of white, in
linear light) and the lamp hardly darker (0.68 to 0.67). A slider called Highlights that brightens
the shadows is not what a photographer expects. With the decision below the field stays at 0.036 and
the lamp goes to 0.55.

Neither the original spektrafilm nor its Rust port has such controls (checked on 2026-11-24): the
closest are the print's curve factors, already in the "Paper curves" group, which change the paper's
contrast and not the scene.

## Decision

- Highlights and shadows are **light**, not contrast: each takes light from, or gives light to, one
  end of the scene, as a reflector, a flag or a graduated filter would at the shot. Every pixel is
  multiplied by a gain that depends on its own luminance alone: nothing at middle gray, growing
  smoothly to two stops at the end of a slider, over six stops of shadows and five of highlights, and
  constant beyond. The three channels take the same gain, so the color of the light stays. The curve
  is never so steep that a brighter part of the scene ends up darker than a darker one. The film,
  the paper and the scan then answer that scene as they would any other: the look stays the engine's.
- They act **after the meter and the exposure, before the film**: the scene's middle gray is where
  the meter and the exposure compensation put it, so a change of exposure changes what counts as a
  shadow, and the two sliders leave middle gray where it was.
- So that the meter does not answer them, **the meter is read first**: the bridge reports what the
  engine's own meter reads for a picture (`SourceImage.metered_ev`, the upstream function, no port),
  the decoder reads it on the photo decoded small without the change of light, puts that exposure
  into the pixels together with the change, and the film is exposed with the meter off
  (`LoadedImage.isMetered`). A Rust test checks that pixels scaled by the metered exposure and
  rendered with the meter off are the photo the engine would have exposed itself. The exposure
  compensation stays the engine's parameter, since the lab's compensation at the print reads it.
- It is done by a Core Image kernel on the scene-linear pixels, in the decoder, as the lens is
  corrected ([ADR 0012](0012-lens-profiles-from-lensfun.md)): the engine is not patched and gets no
  new parameter. With both sliders at zero nothing of this runs: the photo is decoded and metered
  exactly as before.
- They belong to the look: a recipe carries them, as it carries the exposure.
- In the inspector they are two sliders, from -100 to +100, in view in Shot under a title of their
  own, "Highlights and shadows", right after the exposure they are measured from. They first stood
  in a group of their own under Shot that starts closed
  ([ADR 0018](0018-back-to-the-essential-controls.md): a control comes into view only by the user's
  word): the user, who had tried them in the built app on 2026-11-24 and chosen the group, asked on
  2026-11-25 to have them in the Shot section itself, not in a section apart.

## Alternatives considered

| Option | Why not |
|---|---|
| The gain applied to the pixels and the engine left to meter them | The meter answers: measured, dimming the lamp doubles the brightness of the rest |
| A meter of the app's own | A port of the engine's seven metering methods to keep equal to it; the bridge can ask the engine |
| The meter's exposure added to the exposure compensation instead of the pixels | The lab's compensation at the print would then undo the meter's exposure too |
| A local tone mapping (a blurred mask, as Lightroom's or darktable's tone equalizer) | Keeps local contrast, but draws halos at strong edges and depends on the picture's size, so a preview and an export would differ; a gain by luminance is the same at every size |
| The print's curve factors of spektrafilm | They are the paper's contrast, after the film; they are already in the inspector |
| Apple's highlight and shadow filter | Made for pictures ready for the screen, not for scene-linear light beyond white |

## Consequences

- ADR 0016's "contrast never goes before the film" is narrowed: these two change the light the film
  receives, as the exposure does; contrast and saturation still are the film's and the paper's.
- With either slider moved, a change of exposure or of metering decodes the photo again (as a change
  of white balance does), since the change of light is measured from it. With both at zero, nothing
  changes in speed or in pixels.
- With either slider moved, the photo is metered on a copy 256 pixels wide, the size the engine's
  meter reduces every picture to, and previews and exports share that reading; with both at zero the
  engine meters each size itself, as before. The two readings differ a little on a large photo.
- Lifting the shadows shows the sensor's noise there, as it does in any tool; the film's grain comes
  on top of it.
- The ends of the sliders (two stops, six and five stops of reach) were chosen by reckoning, not yet
  by eye on real photos: they are three numbers in `SceneTone`.
