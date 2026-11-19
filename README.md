# spektrafilm for macOS

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
| 1 | Swift bridge to the Rust engine | in progress |
| 2 | SwiftUI app: open RAW, pick film and paper, live Metal preview, export | planned |
| 3 | Photos editing extension | planned |
| 4 | Finder Quick Action and Shortcuts actions for batch processing | planned |

## Goals

- **Native.** SwiftUI interface, Metal rendering, standard macOS windows,
  menus, shortcuts, undo, and color management through ColorSync.
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
                 SpektrafilmKit (Swift)  ◄── UniFFI bindings
                         │
                         ▼
              spektrafilm-ffi (Rust, this repo)
                         │
                         ▼
     spektrafilm-rs engine (git submodule): film → enlarger → paper → scanner
                         │  display-linear RGB
                         ▼
          Metal preview / ColorSync export (JPEG, HEIC, TIFF)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the details.

## Building

Requirements: a Mac with Apple silicon running macOS 26 (Tahoe) or later, a
recent Xcode (26 or later; CI builds with the latest release), and Rust
(install it from [rustup.rs](https://rustup.rs)).

```bash
git clone --recursive https://github.com/davidelarocca/spektrafilm-macos.git
cd spektrafilm-macos
scripts/build-engine.sh
swift test --package-path apple/SpektrafilmKit
```

`scripts/build-engine.sh` compiles the Rust engine, generates the Swift
bindings and packages them as `SpektrafilmKit`. Add `--universal` to also build
for Intel Macs.

### Engine tests on any platform

The Rust bridge and its tests also build on Linux. There the engine uses
OpenBLAS instead of Apple's Accelerate, compiled from source on the first build
(a few minutes):

```bash
cargo test --release --manifest-path engine/Cargo.toml -p spektrafilm-ffi
```

## Repository layout

```
apple/SpektrafilmKit/      Swift package: engine bindings, image I/O, rendering, export
engine/crates/spektrafilm-ffi/   Rust bridge (UniFFI) and its tests
engine/crates/uniffi-bindgen/    binding generator (build tool)
engine/vendor/spektrafilm-rs/    upstream engine (git submodule, pinned)
scripts/                   build scripts
docs/                      design notes
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
