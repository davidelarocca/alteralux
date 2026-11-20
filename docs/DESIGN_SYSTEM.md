# alteralux for macOS design system

Code: `apple/DesignSystem/`. Gallery: `GalleryView`, shown from its Xcode preview in
`apple/DesignSystem/Sources/DesignSystem/Gallery/GalleryView.swift`.

## Principles

1. Native first: follow macOS conventions and the current system materials before inventing a pattern.
2. One behavior, one component. Things that look alike but behave differently stay separate.
3. Intent over values: callers say what (`Spacing.m`, `Radius.thumbnail`), the design system decides how.
4. Always dark: photos are judged against a neutral dark interface, so the app forces the dark
   appearance and each semantic color has a single value.

## Tokens

| Token family | Type | Tokens | Notes |
|---|---|---|---|
| `Spacing` | `CGFloat` | `xxs`, `xs`, `s`, `m`, `l`, `xl` | 2, 4, 8, 12, 16, 24 pt |
| `Radius` | `CGFloat` | `thumbnail`, `control` | |
| `Typography` | `Font` | `body`, `value`, `badge`, `technical` | built on system text styles |
| `Motion` | `Animation` | `quick`, `standard`, `moving(_:reduced:)` | durations live only here |
| Colors | `Color` | `Color.DS.viewerSurround`, `thumbnailPlaceholder`, `hairline` | in `Colors.xcassets` |

Keep this table in sync with the code. The code wins if they differ.

Content that moves reads `@ReduceMotion` and animates through `Motion.moving(_:reduced:)`, so Reduce
Motion gets no animation, or a fade for a transition.

## Interaction patterns

| Pattern | Use for | Component |
|---|---|---|
| Adjusting a numeric parameter | every slider of the adjustments inspector: the track fills from the neutral value, in grays only | `ParameterSlider` |
| A status over the photo | which rendering is on screen ("Original") | `StatusBadge` |
| Picking among photos | the strip of open photos | `ThumbnailCell` inside a `Button` |
| Blocking decision | destructive or irreversible actions | system alert or confirmation dialog |

## Adding or changing a component

Follow the `ui-change` skill. In short: search, decide reuse, extend or create, implement with tokens,
previews for every state, snapshot tests, registry update in the same change.
