# spektrafilm for macOS architecture

Hub document. Keep it short: it is imported into every Claude session. Detail lives in the linked documents.

```
RAW / TIFF / EXR ─► Core Image ─► scene-linear RGB ─► Rust engine ─► display-linear RGB ─► viewer / export
```

## Modules

| Module | Where | Responsibility | May depend on |
|---|---|---|---|
| App shell | `apple/Spektrafilm/` | `@main` scene, resources, entitlements, signing | SpektrafilmUI |
| SpektrafilmUI | `apple/SpektrafilmKit/Sources/SpektrafilmUI/` | App model, screens, menu commands | SpektrafilmKit, SpektrafilmEngine, DesignSystem |
| DesignSystem | `apple/DesignSystem/` | Tokens and shared components | nothing app-specific |
| SpektrafilmKit | `apple/SpektrafilmKit/Sources/SpektrafilmKit/` | Image decoding, settings, rendering, export. No UI | SpektrafilmEngine |
| SpektrafilmEngine | `apple/SpektrafilmKit/Sources/SpektrafilmEngine/` | Generated UniFFI bindings and the engine XCFramework | nothing |
| Engine bridge | `engine/crates/spektrafilm-ffi/` | Rust API exposed to Swift | the upstream engine |
| Upstream engine | `engine/vendor/spektrafilm-rs/` | The film simulation (git submodule, never patched here) | nothing of ours |

The dependencies between the Swift targets are enforced by `docs/architecture-contracts.json`.

## Data flow

One state pattern: `AppModel`, an `@Observable` class on the main actor, injected with `.environment(_:)`.
Views read it and send intents; they hold no business logic. Decoding, rendering and export run off the
main actor (`ImageLoader`, `FilmRenderer`, `ImageExporter` in SpektrafilmKit).

The engine works linear in, linear out: every transfer function and color conversion is done by macOS
(Core Image, ColorSync), never by the engine. Parameters cross the bridge as a JSON patch over the engine
defaults, and unknown keys are errors.

## Protected areas

- `apple/Spektrafilm/Spektrafilm.entitlements`, `apple/Spektrafilm/Info.plist` and
  `apple/Spektrafilm/Signing.xcconfig`: the app's security settings (sandbox, hardened runtime, signing).
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
