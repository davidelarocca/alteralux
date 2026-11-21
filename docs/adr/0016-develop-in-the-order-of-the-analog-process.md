# ADR-0016: The adjustments in the order of the analog process, and an exposure that brightens

- Status: Accepted
- Date: 2026-11-21

## Context

The inspector had grown a Camera section that mixed what the app does to the photo before the engine
(white balance, lens correction) with the engine's own camera (exposure, metering, film format), and
the film's grain and halation in a section of their own. The user asked on 2026-11-21 to define it
properly: some changes must happen before the photo reaches spektrafilm (white balance, exposure, lens
correction, and others to come), and spektrafilm must then work from them; nothing spektrafilm offers
may be left out; and the exposure slider "does not work".

Measured on a test card: the developed photo's mean brightness was 111, 112 and 111 at -2, 0 and +2 EV.
The engine prints the negative to a normal density by default (`enlarger.print_exposure_compensation`):
the exposure changes the negative's character, not the photo's brightness. With that off it is 35, 112
and 199. The engine's exposure is applied to the scene before the film, after its own metering.

## Decision

- The inspector follows the analog process: the film's name as the heading (the look), then Shot (the
  photo as the camera took it, set before the film sees it: exposure and metering, white balance, lens
  correction, cropping), Film (format, development, grain, halation), Print (scan directly, paper, print
  exposure, filters, paper development, the lab's compensation) and Scan (sharpening).
- The exposure stays the engine's, which acts before the film and keeps its metering, and moves to
  Shot. Whether the lab compensates it becomes a visible switch of the print, "The lab compensates the
  exposure": off for new photos, so the exposure brightens and darkens; on, as the engine has it, for
  adjustments saved before, so they look as they did.
- What comes next, in this order (the user's choice): every control spektrafilm offers and the app
  hides, with the technical ones under "More adjustments" in each section; then new tools of the shot
  from Apple's RAW decoder (highlight recovery, noise reduction). Contrast and saturation never go
  before the film, which makes them; retouches after the scan are left for later.

## Alternatives considered

| Option | Why not |
|---|---|
| A pre-film exposure of our own, with our own metering | The engine's exposure already acts before the film; a gain of ours would be undone by its metering, or need a port of it |
| Turning the lab's compensation off with no switch | Leaves out a behaviour of spektrafilm (exposing a negative for its character) |
| Keeping the sections and only moving rows | Leaves the app's and the engine's controls mixed, which is what was asked to change |

## Consequences

- New photos brighten with the exposure; photos developed before keep their look, with the switch on.
- A recipe saved before keeps the lab's compensation on, as its photos had it.
- The expanded state of the old Camera and Film Character sections is not carried to Shot and Film.
