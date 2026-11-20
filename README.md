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

| Phase | What | State |
|---|---|---|
| 1 | Swift bridge to the Rust engine | done |
| 2 | SwiftUI app: open RAW, pick film and paper, live preview, export | in progress |
| 3 | Photos editing extension | planned |
| 4 | Finder Quick Action and Shortcuts actions for batch processing | planned |

Implemented so far (engine, image decoding and export are covered by automated
tests; the interface is young and needs testing on real photos): opening RAW,
TIFF, HEIC, JPEG, PNG and EXR files, choosing
film and paper, the main adjustments with a live preview, zoom, comparison with
the original, several photos side by side in a strip, and export to JPEG,
10-bit HEIC, 16-bit TIFF or PNG with an embedded sRGB or Display P3 profile.

## Goals

- **Native.** SwiftUI interface, standard macOS windows, menus and shortcuts,
  and color management through ColorSync. English and Italian.
- **Faithful.** Same pixels as the reference engine. The bridge has tests that
  compare its output with direct calls to the upstream pipeline.
- **Fast.** The GPU (Metal) preview updates while you drag the sliders; full
  resolution renders run on export.
- **Integrated.** RAW decoding with Apple's own Core Image RAW engine (the one
  Photos uses), a Photos editing extension, Finder Quick Actions and Shortcuts.

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
export.

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
scripts/                         setup, build and verification scripts
docs/                            architecture, design system, decisions, roadmap
```

## License and credits

This project is free software under the **GNU General Public License v3.0 or
later** (see [LICENSE](LICENSE)), as required by the projects it builds on.

- Spectral model, film and paper profiles: [spektrafilm](https://github.com/andreavolpato/spektrafilm)
  © Andrea Volpato, GPLv3. Profiles are licensed CC BY-SA 4.0.
- Rust engine: [spektrafilm-rs](https://github.com/turbasvin/spektrafilm-rs)
  © turbasvin, GPLv3.

If you use spektrafilm in academic work, please cite it as described in its
[CITATION.cff](https://github.com/andreavolpato/spektrafilm/blob/main/CITATION.cff).
