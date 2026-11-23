# ADR-0018: The inspector goes back to the essential controls

- Status: Accepted
- Date: 2026-11-23

## Context

[ADR 0016](0016-develop-in-the-order-of-the-analog-process.md) put every control of spektrafilm's own
interface in the inspector, and the app's on top: some seventy. [ADR 0017](0017-in-view-what-a-photographer-uses.md)
kept few in view and moved the rest under "More … adjustments", with names, help and one rule for
governed controls. The user looked at the result on 2026-11-23 and turned it down: the sidebar never
ends, and many controls do what others already do. Measured the same day on two pictures, a good part
of the detail controls changed the developed photo by less than one level in 255.

What the user asked for: spektrafilm's controls, and before them the few that make the photo ready
for spektrafilm, as asked from the start: exposure, white balance, perhaps a basic contrast
(highlights and shadows), and the lens corrected from the database for distortion and vignetting. With
the lens, the halation at most. Nothing else.

## Decision

- The inspector has about fifteen controls and no "More … adjustments":
  - **Shot**: the meter and the exposure; the automatic white balance, temperature and tint; under
    "Lens", the lens correction and the film's halation.
  - **Film**: format, development where the film offers it, grain, color separation.
  - **Print**: scan directly, paper, print exposure, yellow and magenta filters, paper development
    where the paper offers it, pre-flash.
  - **Scan**: sharpening.
- Gone from the inspector: the metering method; the RAW decoder's noise reduction, color noise, moiré
  and highlight recovery; the diffusion filter and the lens blur; the details of the grain, of the
  halation and scatter, of the color separation; the glare, the pre-flash's own filters, the paper's
  curves; the sharpening's radius, the scanner's blur and its white and black points; the color
  options.
- What is gone stays as spektrafilm sets it, and as Apple's decoder sets it for the RAW. A photo
  developed before keeps the values it has, and so does a recipe; a section's reset puts back what it
  no longer shows too.
- "The lab compensates the exposure" is shown only on a photo that has it on (one developed before
  ADR 0016), so that it can be turned off there; off, it is gone.
- Highlights and shadows before the film come next, on their own, to be judged apart.
- From ADR 0017 stay: the order of a section (modes first), names a photographer uses, a help and a
  unit on each control, a section's own reset and mark of change, and governed controls disabled in
  view with a line that says why (the temperature and tint under the automatic white balance).

## Alternatives considered

| Option | Why not |
|---|---|
| Keeping the details under "More … adjustments", closed | It is the list the user turned down: closed, it is still there to scroll |
| Removing the settings themselves, not only their controls | Photos and recipes that hold them would change their look |
| Keeping the RAW decoder's noise reduction in view | Not spektrafilm's, and not among what the user asked for before the film |
| The halation left in Film | The user wants it with the lens, the one effect allowed there |

## Consequences

- ADR 0016's "every control of spektrafilm is offered" no longer holds; its order of the sections
  does.
- A photo whose hidden values were changed shows its section as changed; Reset puts them back.
- The engine parameters the app sends are the same: the parity test with the engine's defaults stays.
- A control comes back only by the user's word, one at a time.
