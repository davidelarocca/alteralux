# alteralux for macOS

A native macOS app for spectral simulation of analog film: a SwiftUI app around the spektrafilm-rs Rust engine.

## Commands
- First time in a clone or worktree (builds the Rust engine, generates the Xcode project): `scripts/bootstrap.sh`
- Fast check (runs automatically before each turn ends): `scripts/verify.sh fast`
- Full check (before merging a branch): `scripts/verify.sh full`
- Lint: `swiftlint lint --quiet`
- Format: `swiftformat .`
- Open in Xcode: `open apple/Alteralux.xcodeproj` (generated, not committed)
- Engine tests only: `cargo test --release --manifest-path engine/Cargo.toml -p alteralux-ffi`

## Where things are
- Architecture hub, module map, links to all docs: @docs/ARCHITECTURE.md
- Design system rules and tokens: `docs/DESIGN_SYSTEM.md`
- Reusable components, one line each: `docs/COMPONENT_REGISTRY.md`
- Entities, their pages, relations and actions: `docs/PRODUCT_MAP.md`
- Window sizes each main screen must hold, and where popovers open: `docs/LAYOUT_CONTRACT.md`
- Traps that already cost time: `docs/PITFALLS.md`
- Where the product is going and what version 1.0 means: `docs/VISION.md`
- What is done and what comes next: `docs/ROADMAP.md`
- Decisions already taken, do not reopen without a new ADR: `docs/adr/`
- Design system code: `apple/DesignSystem/`
- Screens and app model: `apple/AlteraluxKit/Sources/AlteraluxUI/`

## Non-negotiable rules
- The code is the source of truth. If docs and code disagree, say so and ask.
- UI: reuse before creating. Check `docs/COMPONENT_REGISTRY.md` and search the code before adding any view, style or modifier.
- Product coherence: before showing an entity in a new place, read `docs/PRODUCT_MAP.md`. From there the user can open it, reach the related entities shown with it, and use its usual actions.
- Layout: a screen in `docs/LAYOUT_CONTRACT.md` must fit at every size of its row. Change its layout only with its sizes in mind, and keep the contract and its layout tests in the same change.
- No raw visual values outside the design system: colors, font sizes, spacing, radii and animation durations come from tokens. <!-- check: lint ds_hardcoded_color --> <!-- check: lint ds_hardcoded_font_size --> <!-- check: lint ds_hardcoded_padding --> <!-- check: lint ds_hardcoded_spacing --> <!-- check: lint ds_hardcoded_radius --> <!-- check: lint ds_hardcoded_animation -->
- Views do not own business logic and never talk to the engine directly: they read `AppModel` and send it intents. Decoding, rendering and export go through `AlteraluxKit`.
- Never patch `engine/vendor/spektrafilm-rs/` (the upstream engine, a git submodule). macOS-specific code lives in this repository.
- The film look must stay the engine's: the bridge moves pixels and parameters, it never changes them. A change to `engine/crates/alteralux-ffi/` keeps the test that compares its output with the upstream pipeline.
- `apple/Alteralux/Alteralux.entitlements`, `apple/Alteralux/Info.plist` and `apple/Alteralux/Signing.xcconfig` are protected. Changes there need an explicit request and a plan first. <!-- check: guard -->
- Snapshot baselines (`snapshots/`) change only when the user approves new images with `/swift-harness:approve-snapshots`. A failing snapshot is either a defect to fix or a change to show the user. <!-- check: snapshot baselines -->
- Security settings (entitlements, App Transport Security, sandbox and hardened runtime build settings) are never relaxed to make something work. A change fails the end-of-turn check until the user approves it with `/swift-harness:approve-security`; propose the narrowest option and ask. <!-- check: security settings -->
- Protected paths are changed only through Edit or Write, where the user is asked. Do not change them with shell commands (`sed`, `cp`, `mv`, `rm`); such changes are reported to the user. <!-- check: protected paths -->
- Concurrency escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `assumeIsolated`) are not a way to make code compile. When one is needed, give the reason on the same line: `// concurrency: <why it is safe>`. <!-- check: lint concurrency_unchecked_sendable --> <!-- check: lint concurrency_nonisolated_unsafe --> <!-- check: lint concurrency_preconcurrency --> <!-- check: lint concurrency_assume_isolated -->
- Do not edit `project.pbxproj` by hand: the Xcode project is generated from `apple/project.yml`. Add files through the file system; after adding one to the app target, run `scripts/bootstrap.sh --skip-engine`.
- A new user-facing string needs its Italian translation in `apple/Alteralux/Resources/Localizable.xcstrings`.
- The repository is public: no personal data, tokens or private context in code, docs or commit messages.
- One feature per branch. Do not rewrite unrelated code while implementing a feature.

## Definition of done
- `scripts/verify.sh fast` passes.
- New or changed shared components have previews for every state and an updated registry entry.
- Behavior changes have a test. Visual changes to shared components have a snapshot.
- Report what you verified and what you could not verify. Never claim a check passed without running it.
- Significant architectural choices are recorded as an ADR.
