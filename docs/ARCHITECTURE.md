# alteralux for macOS architecture

Hub document. Keep it short: it is imported into every Claude session. Detail lives in the linked documents.

```
RAW / TIFF / EXR ─► Core Image ─► scene-linear RGB ─► Rust engine ─► display-linear RGB ─► viewer / export
```

## Modules

| Module | Where | Responsibility | May depend on |
|---|---|---|---|
| App shell | `apple/Alteralux/` | `@main` scene, resources, entitlements, signing, the Finder's Services entry and the Shortcuts action | AlteraluxUI |
| AlteraluxUI | `apple/AlteraluxKit/Sources/AlteraluxUI/` | App model, screens, menu commands | AlteraluxKit, AlteraluxEngine, DesignSystem |
| DesignSystem | `apple/DesignSystem/` | Tokens and shared components | nothing app-specific |
| AlteraluxKit | `apple/AlteraluxKit/Sources/AlteraluxKit/` | Image decoding, settings, rendering, export. No UI | AlteraluxEngine |
| AlteraluxEngine | `apple/AlteraluxKit/Sources/AlteraluxEngine/` | Generated UniFFI bindings and the engine XCFramework | nothing |
| Engine bridge | `engine/crates/alteralux-ffi/` | Rust API exposed to Swift | the upstream engine |
| Upstream engine | `engine/vendor/spektrafilm-rs/` | The film simulation (git submodule, never patched here) | nothing of ours |

The dependencies between the Swift targets are enforced by `docs/architecture-contracts.json`.

## Data flow

One state pattern: `AppModel`, an `@Observable` class on the main actor, injected with `.environment(_:)`.
Views read it and send intents; they hold no business logic. Decoding, rendering and export run off the
main actor (`PhotoDecoder`, `FilmRenderer`, `ImageExporter` in AlteraluxKit).

The selected photo is decoded for each preview at the size of that preview, and whole for the 100% view
and for export. White balance is chosen in the RAW decoder, before the engine sees the photo, and so is
the lens corrected: by Apple's decoder where it knows the lens, otherwise with the corrections the camera
recorded in the RAW (Sony, Fujifilm, Nikon Z, Olympus, Panasonic) or with lensfun's profiles, and the
vignetting from the camera where Apple's decoder leaves it, by Core Image kernels (`Lens/` in
AlteraluxKit), before the frame. The scene's highlights and shadows are changed there too, after the
engine's meter has read the photo and before the film sees it. The automatic exposure and the automatic
white balance read the photo as it was shot, whole and with the camera's white balance: no adjustment
changes what they find.

A photo's adjustments are kept in the photo itself, as an extended attribute, and read back when it is
opened again. Undo and redo are the window's own.

A recipe is a look saved under a name: every adjustment but the white balance, the lens correction, the
frame and the RAW decoder's noise reduction, which belong to the photo. Recipes are kept by the
app, one file each; a photo that receives one keeps only the adjustments. A recipe also holds the files
it writes when photos are developed with it (format, size, name, beside the photos, in a folder beside
them or in one folder), and whether the exposure and the white balance were automatic when it was
saved, so each photo starts from its own light. Developing with a recipe only writes files: the photos
keep their adjustments. The Finder's "Develop with alteralux…" (a Services entry) develops the selected
photos at once with a recipe, and the Shortcuts action does the same; a folder outside the library is
written into only once the user grants it, and remembered.

The library shows the folders the user adds as they are on disk: it reads them, remembers them with
security-scoped bookmarks and reads them again when they change. It keeps no catalogue.

The engine works linear in, linear out: every transfer function and color conversion is done by macOS
(Core Image, ColorSync), never by the engine. Parameters cross the bridge as a JSON patch over the engine
defaults, and unknown keys are errors.

## Protected areas

- `apple/Alteralux/Alteralux.entitlements`, `apple/Alteralux/Info.plist` and
  `apple/Alteralux/Signing.xcconfig`: the app's security settings (sandbox, hardened runtime, signing).
  They are never relaxed to make something work.
- `engine/vendor/spektrafilm-rs/`: the upstream engine. Updating it means moving the submodule pointer;
  anything macOS-specific lives in this repository.

## Documents

- The engine bridge and its guarantees: [ENGINE_BRIDGE.md](ENGINE_BRIDGE.md)
- The Swift modules and the app at run time: [SWIFT_SIDE.md](SWIFT_SIDE.md)
- Design system: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)
- Component registry: [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md)
- Product map (entities, destinations, relations, actions): [PRODUCT_MAP.md](PRODUCT_MAP.md)
- Layout contract (window sizes per screen, presented UI): [LAYOUT_CONTRACT.md](LAYOUT_CONTRACT.md)
- Pitfalls that already cost time: [PITFALLS.md](PITFALLS.md)
- Vision: what the product is meant to become and what 1.0 means: [VISION.md](VISION.md)
- Roadmap and next steps: [ROADMAP.md](ROADMAP.md)
- Decisions: `docs/adr/` (index below)

## Decision index

| ADR | Title | Status |
|---|---|---|
| [0001](adr/0001-reuse-the-rust-engine.md) | Reuse the spektrafilm-rs engine through a UniFFI bridge | Accepted |
| [0002](adr/0002-linear-in-linear-out.md) | Keep the engine linear in, linear out | Accepted |
| [0003](adr/0003-generate-the-xcode-project.md) | Generate the Xcode project with XcodeGen | Accepted |
| [0004](adr/0004-ui-in-packages.md) | Keep the screens and the design system in Swift packages | Accepted |
| [0005](adr/0005-organize-through-the-finder.md) | Organize photos through the Finder, with no catalogue of the app's own | Accepted |
| [0006](adr/0006-use-the-systems-controls.md) | Build the interface from the system's controls | Accepted |
| [0007](adr/0007-decode-each-preview-at-its-size.md) | Decode each preview at its size, with Core Image | Accepted |
| [0008](adr/0008-keep-edits-in-the-photo.md) | Keep a photo's adjustments in the photo itself | Accepted |
| [0009](adr/0009-recipes-are-looks-kept-by-the-app.md) | A recipe is a look without white balance, kept by the app | Accepted |
| [0010](adr/0010-crop-before-the-engine.md) | Crop and straighten before the engine | Accepted |
| [0011](adr/0011-recipes-adapt-to-each-photo.md) | Recipes that adapt to each photo, and the lens corrected by the RAW decoder | Accepted; adapting follows the recipe's Auto switches since 0021 |
| [0012](adr/0012-lens-profiles-from-lensfun.md) | Lens profiles from lensfun's database, applied before the engine | Accepted |
| [0013](adr/0013-workflows-are-recipes-with-their-files.md) | A workflow is a recipe and the files it writes, kept beside the recipes | Superseded by 0021 |
| [0014](adr/0014-finder-and-shortcuts-hand-photos-to-the-app.md) | A workflow is how a recipe is used, run from the Finder's right-click menu and from Shortcuts | Accepted; the workflow is the recipe's files since 0021 |
| [0015](adr/0015-the-cameras-own-lens-corrections.md) | The corrections cameras record, combined with Apple's decoder and lensfun | Accepted |
| [0016](adr/0016-develop-in-the-order-of-the-analog-process.md) | The adjustments in the order of the analog process, and an exposure that brightens | Accepted; what is in view set by 0018 |
| [0017](adr/0017-in-view-what-a-photographer-uses.md) | In view what a photographer uses, the rest under the control it belongs to | Accepted; "More … adjustments" removed by 0018; the automatic modes' sliders out of view by 0020 |
| [0018](adr/0018-back-to-the-essential-controls.md) | The inspector goes back to the essential controls | Accepted |
| [0019](adr/0019-highlights-and-shadows-before-the-film.md) | Highlights and shadows as light, after the meter and before the film | Accepted; the two sliders in view in Shot since 2026-11-25; what the meter reads set by 0022 |
| [0020](adr/0020-automatic-means-automatic.md) | Automatic means automatic: a mode's switch on its title, its sliders out of view | Accepted |
| [0021](adr/0021-a-recipe-holds-its-files.md) | A recipe holds the look and the files it writes; workflows go | Accepted |
| [0022](adr/0022-the-automatic-modes-read-the-photo-as-shot.md) | The automatic exposure and white balance read the photo as it was shot | Accepted |
| [0023](adr/0023-a-preview-looks-like-the-photo-seen-at-its-size.md) | A preview looks like the developed photo seen at its size | Accepted |
| [0024](adr/0024-the-dropper-makes-the-point-clicked-gray.md) | The dropper makes the point clicked gray | Proposed |
