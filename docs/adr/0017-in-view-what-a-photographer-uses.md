# ADR-0017: In view what a photographer uses, the rest under the control it belongs to

- Status: Accepted
- Date: 2026-11-23

## Context

After [ADR 0016](0016-develop-in-the-order-of-the-analog-process.md) the inspector offered every control
of spektrafilm and the app's own: some seventy. A control and its details were in two places with
nothing that tied them; a control governed by another was hidden in some places and disabled in
others; several kept the engine's names, and many had no help.

The user asked on 2026-11-22 for clearer sub-controls and gave the direction for the product. The core
is what spektrafilm does (film, print, scan) and the controls that prepare the photo before it
(exposure, temperature, tint and the like): this stays in the foreground. More functions may be added
where they are really good, but the first rule is not to end with a very long list that confuses,
where nobody can tell what each control does. Better fewer things, finished well.

## Decision

- **In view, in each section, only the few controls a photographer really uses.** The rest is under
  "More … adjustments", grouped under a subheading that has the name of the control it belongs to
  (`InspectorSubheading`), which says when that control is off.
- **One order in every section**: the modes first (automatic, on or off, scan directly), then the main
  sliders, then the refinements. A control that governs others is above them.
- **One rule for a governed control**: it stays in view, disabled, with a line that says why, which
  VoiceOver reads on each control (`governed(_:reason:)`). The line is written once for a group, and
  left out where the switch is the row right above. Hidden only where a whole group has no sense: the
  print when the film is scanned directly, the metering method without the meter.
- **A switch that only turns a slider on is on the slider's own row** (grain, halation, color
  separation, diffusion filter, glare, white and black point).
- **Names a photographer uses**; the technical name is in the help. Every control has a help of one
  sentence that says what changes in the photo and in which direction, and shows its unit.
- **A control that cannot be explained to a photographer in one sentence, or that does not change the
  photo visibly, is a candidate to remove or to merge.** It is noted for the user, who decides; the
  list is in [ROADMAP.md](../ROADMAP.md).
- **A new function enters only if it is clear and seen in the photo**, and whoever proposes it says
  what gets simpler to make room for it.
- Each section is reset alone and shows when it was changed; closed, its summary names the modes that
  are on.
- Controls and names move; values and defaults do not. A photo developed before looks as it did.

## Alternatives considered

| Option | Why not |
|---|---|
| Hiding a governed control | Controls come and go as modes change, and their place cannot be learned; two rules were what had to end |
| Removing the engine's technical controls now | ADR 0016 offers everything spektrafilm does; what goes is the user's choice, one control at a time |
| A separate "advanced" window | Takes the details away from the control they shape |
| The technical name beside each label | Names nobody asked for on every row; the help has room for them |

## Consequences

- The Shot section loses its Crop row (the toolbar has Crop) and gains the diffusion filter's kind and
  the RAW development the decoder offers; the metering method sits under the meter's switch.
- With the meter on, the exposure reads as a compensation; where the lab compensates the print, a line
  under it says the exposure changes the negative instead.
- Print exposure is shown in stops, glare and pre-flash in percent; values on disk are unchanged.
- Scatter stays switched with the halation, as the engine applies it; the subheading says so.
- "Every control of spektrafilm is offered" (ADR 0016) holds until the user decides on the candidates.
