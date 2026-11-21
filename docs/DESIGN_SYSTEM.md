# alteralux for macOS design system

Code: `apple/DesignSystem/`. Gallery: `GalleryView`, shown from its Xcode preview in
`apple/DesignSystem/Sources/DesignSystem/Gallery/GalleryView.swift`.

## Principles

1. Native first: controls are the system's (`Slider`, `Toggle`, `Picker`, collapsible `Section`s, `List`,
   `Form`), drawn and laid out as the system does: its accent color, its margins, the window's own title.
   A component wraps one to add what the app needs around it, never to redraw it
   ([ADR 0006](adr/0006-use-the-systems-controls.md)). The mockups guide structure, not the drawing of
   controls.
2. One behavior, one component. Things that look alike but behave differently stay separate.
3. Intent over values: callers say what (`Spacing.m`, `Radius.thumbnail`), the design system decides how.
4. Always dark: photos are judged against a neutral dark interface, so the app forces the dark
   appearance and each semantic color has a single value.

## Tokens

| Token family | Type | Tokens | Notes |
|---|---|---|---|
| `Spacing` | `CGFloat` | `xxs`, `xs`, `s`, `m`, `l`, `xl` | 2, 4, 8, 12, 16, 24 pt |
| `Radius` | `CGFloat` | `thumbnail`, `control`, `emblem` | |
| `Typography` | `Font` | `body`, `heading`, `sheetTitle`, `caption`, `emblem`, `value`, `badge`, `technical` | built on system text styles |
| `SheetSize` | `CGFloat` | `width` | 420 pt: every sheet has it |
| `Motion` | `Animation` | `quick`, `standard`, `moving(_:reduced:)` | durations live only here |
| Colors | `Color` | `Color.DS.viewerSurround`, `thumbnailPlaceholder`, `hairline` | in `Colors.xcassets` |
| Emblem inks | `FilmEmblem.Ink` | `violet`, `gold`, `petrol`, ... | the colors film emblems are made of; used only there |

Keep this table in sync with the code. The code wins if they differ.

Content that moves reads `@ReduceMotion` and animates through `Motion.moving(_:reduced:)`, so Reduce
Motion gets no animation, or a fade for a transition.

## Interaction patterns

| Pattern | Use for | Component |
|---|---|---|
| Adjusting a numeric parameter | every slider of the adjustments inspector and the zoom: the system slider, filled from the neutral value | `ParameterSlider` |
| A parameter that can be switched off | grain, halation: the switch on the slider's row | `ParameterSlider` with `isOn` |
| A group of controls the user can collapse | the sections of the inspector; collapsed, a section shows its values | `InspectorSection` |
| The one thing a pane is about | the film at the top of the inspector, which opens the list of films | `HeadingButton` |
| Telling items of a list apart | the films in the list of films | `FilmEmblem` in a row of a `List` |
| Switching something on or off | every other switch | `Toggle` in a `Form` |
| Choosing among a few named options | paper, film format, development times | `WindowPopUp` in a `Form`: the system's pop-up button, its menu kept inside the window |
| A status over the photo | which rendering is on screen ("Original") | `StatusBadge` |
| Picking among photos | the strip of open photos | `ThumbnailCell` inside a `Button` |
| Actions on what is selected | the selected photos of the library | `FloatingBar`: it floats on glass over the content near its bottom edge while something is selected |
| Controls floating over the photo | the crop's controls under the photo being cropped; the zoom, over the photo's bottom trailing corner | `GlassGroup` on the system's glass, with Cancel and Done as round glass buttons beside the crop's |
| A menu on the trailing side of the toolbar | the recipes | `WindowMenuButton`: the system's menu, opened under the button and moved to stay inside the window; no submenus |
| Choosing from a bar near the bottom of the window | a recipe, a folder or a tag for the selected photos | `ChoiceListButton`: its list opens above it, inside the window, where a menu would open downward and leave it |
| A pane that scrolls | the adjustments, the library, its folders, the films | `.thinScrollBars()`: the thin bars that show while scrolling, as the photo viewer's |
| Blocking decision | destructive or irreversible actions | system alert or confirmation dialog |
| Asking for a name | the name of a new recipe, another name for one | system alert with a text field |
| Options before acting, or a progress that can be stopped | export options, the export of several photos | `FormSheet`: it follows the look of the system's alert (bold title, wide round buttons), so the two read as one family |

## Adding or changing a component

Follow the `ui-change` skill. In short: search, decide reuse, extend or create, implement with tokens,
previews for every state, snapshot tests, registry update in the same change.
