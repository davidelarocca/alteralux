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

- The inspector follows the original spektrafilm, whose interface opens with a handful of controls
  in view and keeps the rest of its some 120 in groups that start closed (read from its source on
  2026-11-24: in view, film and paper, automatic exposure and its compensation, the print's automatic
  compensation and exposure, the yellow and magenta filters, scan the film).
- **In view**, about fifteen controls:
  - **Shot**: the meter, its method and the exposure; the automatic white balance, temperature and
    tint; under "Lens", the lens correction and the film's halation.
  - **Film**: format, development where the film offers it, grain.
  - **Print**: scan directly, the lab's compensation of the exposure, paper, print exposure, yellow
    and magenta filters, paper development where the paper offers it.
  - **Scan**: sharpening.
- **Everything else, in groups that start closed**, one per kind, right under the section they
  belong to (`DetailGroup`): the lens blur and the diffusion filter, the RAW development (Shot); the
  grain, the halation and scatter, the color separation (Film); the pre-flash, the glare, the paper's
  curves (Print); the scanner, the color options (Scan). A group stays as the user left it. No
  "More … adjustments" list: nothing is long unless it is opened.
- The first cut, on 2026-11-23, had taken those controls out of the inspector altogether; the user
  found them missing the next day and asked for all of them back, closed as the original has them.
- More than the original has in view, asked by the user or the least a film needs: the white balance
  and the lens correction, the halation, the metering method, the format, the grain, the sharpening.
- Highlights and shadows before the film come next, on their own, to be judged apart.
- From ADR 0017 stay: the order of a section (modes first), names a photographer uses, a help and a
  unit on each control, a section's own reset and mark of change, and governed controls disabled in
  view with a line that says why.

## Alternatives considered

| Option | Why not |
|---|---|
| One "More … adjustments" list per section | Opened, it is the endless list the user turned down; a group per kind is short |
| Taking the detail controls out of the inspector | Tried on 2026-11-23: the user found them missing |
| Keeping the RAW decoder's noise reduction in view | Not spektrafilm's, and not among what the user asked for before the film: it has its group |
| The halation left in Film | The user wants it with the lens, the one effect allowed there |

## Consequences

- ADR 0016's "every control of spektrafilm is offered" no longer holds; its order of the sections
  does.
- A photo whose values in a closed group were changed shows its section as changed; Reset puts them
  back. A closed group does not say by itself that something in it was changed.
- The engine parameters the app sends are the same: the parity test with the engine's defaults stays.
- A control moves into view only by the user's word, one at a time.
