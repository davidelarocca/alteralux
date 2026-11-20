# ADR-0006: Build the interface from the system's controls

- Status: Accepted
- Date: 2026-11-20

## Context

The mockups of 2026-11-20 drew the controls by hand: a thin slider that fills from its neutral point,
switches in grays, sections with their own chevrons, a list of films with its own rows. The slider was
built that way first. Seen in the running app, the result did not read as a Mac app: the user asked for
the elements to be the system's, "like the sliders, the selectors".

macOS 26 gives the system slider a neutral value: it fills from that value to the thumb, which is what
the hand-drawn track was for.

## Decision

- Controls are SwiftUI's: `Slider`, `Toggle`, `Picker`, collapsible `Section`s, `List`, `Form`, `Button`,
  `TextField`, the toolbar with the window's own title and subtitle, popovers. The app does not draw a
  control the system has, and does not replace what the system lays out (the window's title, a form's
  margins).
- A shared component wraps a system control to add what the app needs around it (the value beside a
  slider, the values of a collapsed section), never to redraw it.
- What stays the app's own is content, not controls: the photo, the film emblems.
- The controls look as the system draws them, accent color included. A first attempt tinted them gray,
  to keep saturated color away from the photo: seen in the app the same day, gray switches read as
  switched off and the app did not look native. The tint was removed.

## Alternatives considered

| Option | Why not |
|---|---|
| Hand-drawn controls, as in the mockups | They do not follow the system's design from one release to the next, and each one needs its own keyboard, accessibility and right-to-left work |
| System controls tinted gray | Tried and removed: a gray switch that is on reads as off, a tinted button as disabled, and the result does not look like a Mac app |
| A view of the app's own in the toolbar, with the photo's name between the arrows | Tried and removed: the system already shows the window's title and subtitle, and lays them out with the toolbar's buttons |

## Consequences

- The interface follows macOS: its look changes with the system's, without work here.
- The mockups are a guide to structure (what is where), not to the drawing of the controls.
- Snapshots of components that hold system controls change when macOS changes how it draws them. They
  are pinned to the macOS version they were made on.
- A system slider takes the keyboard focus only with "Keyboard navigation" on: `ParameterSlider` keeps
  taking it itself (see `docs/PITFALLS.md`).
- The accent color shows on the switches that are on and on the selected segment of the zoom: small
  areas, which the vision allows beside the photo.
