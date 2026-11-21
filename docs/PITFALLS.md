# Pitfalls

Traps that already cost real time in this project, or came back. Read this list before starting a task; the checkpoint after a compaction names it. Keep about a dozen entries: when one no longer applies (the code that caused it is gone, or a check now catches it), move it to the archive or delete it.

Each entry: what goes wrong, how it shows, and what to do instead. Link the test or check that now catches it, if any.

## Build and tooling

- **The engine and the Xcode project are build products.** A fresh clone or worktree has neither the
  XCFramework nor the generated Xcode project: `swift build` fails on a missing binary target. Run
  `scripts/bootstrap.sh` once. `scripts/verify.sh` rebuilds them when they are missing or stale.
- **`uniffi-bindgen` must start inside the Cargo workspace.** Run from the repository root it fails with
  "could not find Cargo.toml": it calls `cargo metadata`. `scripts/build-engine.sh` runs it from `engine/`.
- **A cached OpenBLAS is tuned for the machine that built it (Linux CI only).** On another CPU the tests
  die with SIGILL. CI builds it with `OPENBLAS_TARGET=GENERIC` and `OPENBLAS_DYNAMIC_ARCH=1`. macOS uses
  Accelerate and is not affected.
- **`open -a` needs an absolute path to the app.** A relative path gives "Unable to find application".
- **A stepped `Slider` draws a tick mark per step.** Round in the binding instead, as `ParameterSlider` does.
- **Strings in package views are looked up in the app's string catalog.** A new string in `AlteraluxUI`
  or `DesignSystem` needs its entry in `apple/Alteralux/Resources/Localizable.xcstrings`, or it shows in
  English only.

## Data and tests

- UI tests must never open the user's real data: they launch with the isolation arguments in `uiTests.isolation` (the tests rule of the setup says how).
- **Tests of the Swift packages use the real engine and the submodule's data.** They need the submodule
  checked out (`git submodule update --init`) and the engine built.
- **Tests write only to the temporary folder.** The test charts are generated there and removed.
- **Apple's RAW decoder refuses a RAW that is too small, without an error.** For a DNG of 128 × 96 pixels
  `CIRAWFilter` is created, reports a size of zero and gives an empty image; 192 × 128 works. The test
  RAW (`TestDNG`) is 240 × 160, and `PhotoDecoder` reports an image of no size as unreadable.
- **A new `CIRAWFilter` for every decode is three times slower.** A 1024 px decode takes 65 ms from a
  filter kept alive and 200 ms from a new one. Go through the photo's `PhotoDecoder`; `ImageLoader.load`
  is for a file decoded once.

## UI

- **The window follows the system appearance unless told otherwise.** With a dark viewer and a light
  system the title was unreadable and the photo strip white. The app sets the dark appearance at launch.
- **`onOpenURL` delivers one file of a multi-file open.** Three photos opened together from the Finder
  added one to the strip. The files come from AppKit instead (`OpenFilesDelegate`,
  `application(_:open:)`), which hands over all of them; `OpenFilesTests` covers the delegate, and the
  delivery itself was checked by hand on the built app.
- **`value.formatted()` follows the Mac's language, not the view's.** A number formatted into a `String`
  ignores the `\.locale` of the environment, so a view shown in another language keeps the system's
  decimal separator, and a snapshot changes from one Mac to the next. Use `Text(value, format:)`. The
  snapshots of `ParameterSlider` in `en` and `it` catch it.
- **`Text("a") vs Text(condition ? "a" : "b")`.** A ternary of string literals resolves to `String`, which
  is not localized. Build two `Text` values instead.
- **A system `Slider` takes the keyboard focus only with "Keyboard navigation" on.** With the setting off
  (the default) Tab skips it, so its arrow keys and any `onKeyPress` never run. A control that must work
  from the keyboard takes the focus itself with `.focusable(interactions: .edit)`, as `ParameterSlider`
  does. Its accessibility increment is a tenth of the range unless `accessibilityAdjustableAction` says
  otherwise. Caught by `ParameterSliderKeyboardTests`.
- **A trilinear layer filter builds mipmaps on the main thread for every new image.** With
  `minificationFilter = .trilinear` each preview frame cost the main thread about 30 ms at the commit,
  against 0.1 ms with `.linear`, and the sliders stuttered. The viewer asks for mipmaps only when the
  image is shown below half its size (`ImageScrollView.needsMipmaps`, covered by `ViewerTests`).
- **A form's content runs under a scroll bar that is always shown.** With "Show scroll bars: Always" the
  switches of the inspector touched the scroll bar. The form has a wider margin on both sides
  (`.contentMargins(.horizontal, _, for: .scrollContent)`, added to the form's own): a margin on the
  trailing side only left the form off center whenever the scroll bar was not there.
- **A text field does not take the focus in a test process.** `@FocusState` set in `onAppear` works in
  the app and not under `swift test`, where the process is not the active app: keys sent to the window
  go nowhere. A keyboard test makes the field first responder itself, as `FilmPickerTests` does.
- **A gray tint on the system's controls reads as disabled.** A switch that is on looks off, and the
  label of a button in a form takes the tint. The controls keep the accent color
  ([ADR 0006](adr/0006-use-the-systems-controls.md)).
- **A view of our own in the toolbar replaces what the system lays out.** The photo's name between two
  arrows, with the window's title removed, sat in one capsule with the Open button and read as badly
  made. The window keeps `navigationTitle` and `navigationSubtitle`; previous and next are plain toolbar
  buttons beside them.
- **`.onKeyPress(.delete)` does not match the Delete key.** `KeyEquivalent.delete` is U+0008 and the key
  arrives as U+007F: match both.
- **A URL remembers the tags it read.** `resourceValues(forKeys: [.tagNamesKey])` caches on the `URL`,
  and does not see tags written since as the raw attribute `com.apple.metadata:_kMDItemUserTags`. Read
  tags through `PhotoInfoReader.tags(of:)`, which reads the attribute and clears the cache before falling
  back. Set by name through `URLResourceValues.tagNames`, a tag of the user's own loses its color.
- **A symbol in a palette picker is drawn white.** In `.pickerStyle(.palette)` neither `.tint` nor
  `.foregroundStyle` colors an `Image`; it takes its color with `.symbolRenderingMode(.palette)`.
- **A context menu after a view's tap gestures never opens.** On a tile with `onTapGesture` (single,
  double, with modifiers), `.contextMenu` placed after them showed nothing on a secondary click; placed
  before them it works.
- **`ScrollPosition.scrollTo(y:)` counts from the top of the content, not from `contentOffset`.** Under a
  toolbar the offset starts below zero (-52 pt); a position taken from the offset must add the top inset
  back, or the scroll is clamped and nothing moves.
- **Synthesized clicks sent to one process are ignored.** `CGEvent.postToPid` delivers keys, not mouse
  clicks, to a SwiftUI app; checking a gesture in the built app needs real pointer events.
- **A disabled segmented control on glass does not look disabled.** Inside a `GlassGroup` its selected
  segment keeps the accent color, so a switch turned off reads as broken. Do not leave a control there
  that does nothing: make it work, or take it away while it cannot.
- **SwiftUI's `Form` and `List` have no setting for thin scroll bars.** With a mouse connected the system
  draws wide ones that stay. `.thinScrollBars()` finds the `NSScrollView` drawn behind the modifier and sets
  `scrollerStyle = .overlay`, again after each change of the system's preference.
- **Precise scrolling deltas do not mean a trackpad.** Many mice scroll smoothly, in points, and send
  `hasPreciseScrollingDeltas` as a trackpad does: the viewer took the user's wheel for a trackpad and moved
  the photo instead of zooming it. A trackpad's scroll (and a Magic Mouse's) is a gesture, with a `phase`
  and then a `momentumPhase`; a wheel's has neither.
- **Wheel events made with `CGEvent` did not change the viewer** while the real wheel did, and clicks and
  drags made the same way work. Test the wheel's logic by calling `scrollWheel(with:)` with an
  `NSEvent(cgEvent:)`, as `ViewerTests` does, and try the real wheel by hand.
