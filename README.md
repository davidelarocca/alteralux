# alteralux for macOS

A native macOS app for **spectral simulation of analog film photography**:
develop your photos through a virtual negative, enlarger, print paper and
scanner, the way real film works.

> **Independent project.** This is not the official spektrafilm app. Film
> modeling is powered by [spektrafilm](https://github.com/andreavolpato/spektrafilm)
> by Andrea Volpato, through the Rust port
> [spektrafilm-rs](https://github.com/turbasvin/spektrafilm-rs) by turbasvin.
> All the color science comes from their work: please star their repositories
> and consider [supporting Andrea](https://buymeacoffee.com/andreavolpato).

## Status

Early development. Nothing to download yet.

What works today (engine, image decoding and export are covered by automated
tests; the interface is young and needs testing on real photos): opening RAW,
TIFF, HEIC, JPEG, PNG and EXR files, choosing film and paper, the main
adjustments with a live preview, white balance for RAW files, undo and redo,
adjustments that stay with each photo between launches, a library that shows
the folders you add as they are on disk, where photos are moved, copied,
tagged with the Finder's tags and discarded, zoom, comparison with the original,
crop and straighten, lens corrections (Apple's RAW decoder, or lensfun's
profiles), recipes (looks saved under a name, which can adapt to each photo),
workflows that develop photos with a recipe into files, from the library, from
the Finder's right-click menu or from Shortcuts, and export to JPEG, 10-bit
HEIC, 16-bit TIFF or PNG with an embedded sRGB or Display P3 profile.

What it is meant to become, and what version 1.0 means, is in
[docs/VISION.md](docs/VISION.md); what is done and what comes next, in order,
is in [docs/ROADMAP.md](docs/ROADMAP.md). In short, before 1.0: the rest of
the automated interface checks, the icon and a notarized release. An
integration with Photos comes after 1.0.

## Goals

- **Native.** SwiftUI interface, standard macOS windows, menus and shortcuts,
  and color management through ColorSync. English and Italian.
- **Faithful.** Same pixels as the reference engine. The bridge has tests that
  compare its output with direct calls to the upstream pipeline.
- **Fast.** The GPU (Metal) preview updates while you drag the sliders; full
  resolution renders run on export.
- **Integrated.** RAW decoding with Apple's own Core Image RAW engine (the one
  Photos uses), the Finder's folders and tags instead of a catalogue of its
  own, the Finder's right-click menu and Shortcuts.

## How it works

```
 RAW / TIFF / EXR ──► Core Image (CIRAWFilter, ImageIO)
                         │  scene-linear RGB (Rec. 2020)
                         ▼
                 AlteraluxKit (Swift)  ◄── UniFFI bindings
                         │
                         ▼
              alteralux-ffi (Rust, this repo)
                         │
                         ▼
     spektrafilm-rs engine (git submodule): film → enlarger → paper → scanner
                         │  display-linear RGB
                         ▼
        color-managed preview / export (JPEG, HEIC, TIFF, PNG)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the details.

## Building

Requirements: a Mac with Apple silicon running macOS 26 (Tahoe) or later, a
recent Xcode (26 or later; CI builds with the latest release), and Rust
(install it from [rustup.rs](https://rustup.rs)).

```bash
git clone --recursive https://github.com/davidelarocca/alteralux.git
cd alteralux
scripts/setup-mac.sh
open apple/Alteralux.xcodeproj
```

Then press Run in Xcode. `scripts/setup-mac.sh` checks the tools (add
`--install` to install what is missing: Rust, and with Homebrew jq, SwiftLint
and SwiftFormat), then runs `scripts/bootstrap.sh`, which compiles the Rust
engine, generates the Swift bindings and creates the Xcode project (with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), downloaded into `build/`).
The first run takes a few minutes; afterwards
`scripts/bootstrap.sh --skip-engine` regenerates only the project.

The app is signed to run locally, so no Apple developer account is needed. It
is sandboxed: it reads only the photos you open and writes only the files you
export. It keeps each photo's adjustments in an extended attribute of the
photo, which leaves its pixels and its date untouched.

To check everything from the command line (tests of the Swift packages and a
build of the app; `full` adds SwiftLint):

```bash
scripts/verify.sh fast
```

### Working with Claude Code

The repository is set up for [swift-harness](https://github.com/davidelarocca/swift-harness),
a Claude Code plugin that keeps the design system, the layout contract and the
documentation true while the app grows, and runs `scripts/verify.sh fast` at the
end of each turn. `CLAUDE.md` and `.claude/rules/` hold the project's rules;
`docs/ROADMAP.md` says what comes next.

### Engine tests on any platform

The Rust bridge and its tests also build on Linux. There the engine uses
OpenBLAS instead of Apple's Accelerate, compiled from source on the first build
(a few minutes):

```bash
cargo test --release --manifest-path engine/Cargo.toml -p alteralux-ffi
```

## Repository layout

```
apple/Alteralux/               the app shell (scene, resources, entitlements)
apple/AlteraluxKit/            Swift package: engine bindings, image I/O and rendering, screens
apple/DesignSystem/              Swift package: design tokens and shared components
apple/project.yml                Xcode project definition (XcodeGen)
engine/crates/alteralux-ffi/   Rust bridge (UniFFI) and its tests
engine/crates/uniffi-bindgen/    binding generator (build tool)
engine/vendor/spektrafilm-rs/    upstream engine (git submodule, pinned)
third_party/lensfun/             lensfun's lens database, unmodified (CC BY-SA 3.0)
scripts/                         setup, build and verification scripts
snapshots/                       approved images of the components and screens, compared by the tests
docs/                            vision, roadmap, architecture, design system, decisions
```

## License and credits

This project is free software under the **GNU General Public License v3.0 or
later** (see [LICENSE](LICENSE)), as required by the projects it builds on.

- Spectral model, film and paper profiles: [spektrafilm](https://github.com/andreavolpato/spektrafilm)
  © Andrea Volpato, GPLv3. Profiles are licensed CC BY-SA 4.0.
- Rust engine: [spektrafilm-rs](https://github.com/turbasvin/spektrafilm-rs)
  © turbasvin, GPLv3.
- Lens profiles: the [lensfun](https://lensfun.github.io) database © the lensfun
  contributors, CC BY-SA 3.0, shipped unmodified as separate files
  (see [third_party/lensfun](third_party/lensfun/README.md)).

If you use spektrafilm in academic work, please cite it as described in its
[CITATION.cff](https://github.com/andreavolpato/spektrafilm/blob/main/CITATION.cff).
