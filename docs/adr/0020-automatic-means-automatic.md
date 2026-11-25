# ADR-0020: Automatic means automatic: a mode's switch on its title, its sliders out of view

- Status: Accepted
- Date: 2026-11-24

## Context

In Shot the automatic exposure and the automatic white balance were two switches among the rows, each
followed by the sliders it governs: the exposure as a compensation, the temperature and the tint
disabled with a line that says why ([ADR 0017](0017-in-view-what-a-photographer-uses.md): a governed
control stays in view, disabled). The user tried it on 2026-11-24 and said two things: a switch looks
like one more row, not like the head of the controls under it; and with the automatic on, the
controls must fold away and the exposure be really the meter's.

Asked what should stay under the switch, the user chose nothing; told that this leaves no way to make
a look "automatic, but a little brighter", and that a recipe saved by hand gives one fixed exposure to
every photo, they chose to keep the compensation in a closed group.

## Decision

- Exposure and white balance are each a **title with its "Auto" switch on the same row**
  (`InspectorSubheading` with a switch). On: the mode takes care of it and nothing else is shown.
  Off: the sliders appear under the title (the exposure; temperature and tint).
- **The meter's own controls are in a closed group, "Meter"**, under Shot: how it weighs the scene,
  and the exposure compensation, which stays what the engine has, a number of stops added to what the
  meter measured. They are disabled, with a line, while the meter is off.
- **Turning a mode off hands over where it left**: the exposure slider starts at what the meter had
  chosen with its compensation (the bridge reports the meter's reading,
  [ADR 0019](0019-highlights-and-shadows-before-the-film.md)), and temperature and tint at what the
  automatic white balance gave, as chosen by hand. The photo does not change until a slider moves.
  Turning the automatic exposure on starts from no compensation.
- The adjustments are stored as before (`autoExposure`, `exposureEV`, `autoWhiteBalance`,
  `temperature`, `tint`): nothing saved changes its look.

## Alternatives considered

| Option | Why not |
|---|---|
| The governed sliders in view, disabled (ADR 0017) | What the user turned down: the section stays long and the switch does not read as their head |
| No compensation at all with the automatic exposure | No look that is automatic and brighter; a slide scanned directly has no print exposure to turn to |
| The compensation in view under the switch | Offered and not chosen: Shot stays compact |
| Turning the meter off leaves the slider at 0 | The photo jumps to the exposure as shot, often stops away from what was on screen |

## Consequences

- ADR 0017's rule for governed controls no longer holds for these two modes: what an automatic mode
  sets leaves the view. It still holds where a switch turns a parameter off (grain, halation, the
  diffusion filter and their details).
- Of what [ADR 0018](0018-back-to-the-essential-controls.md) lists in view for Shot, the metering
  method moves to the meter's group.
- With the automatic on, the inspector does not show the values it chose; the collapsed section's
  summary still does.
- A recipe carries whether the exposure is automatic, as before, and since
  [ADR 0021](0021-a-recipe-holds-its-files.md) whether the white balance is.
