# ADR-0001: Reuse the spektrafilm-rs engine through a UniFFI bridge

- Status: Accepted
- Date: 2026-11-19

## Context

The spectral film model is about 10 000 lines of Python in spektrafilm, ported to about 27 000 lines of
Rust in spektrafilm-rs. The Rust port is verified against the Python reference and already renders on
Metal through wgpu. A native macOS app needs that model behind a Swift API.

## Decision

Use spektrafilm-rs unmodified, as a git submodule pinned to a commit (`engine/vendor/spektrafilm-rs`).
Expose it to Swift through one small Rust crate, `engine/crates/spektrafilm-ffi`, with bindings generated
by UniFFI. Never patch the submodule: macOS-specific code lives in this repository.

## Alternatives considered

| Option | Why not |
|---|---|
| Rewrite the model in Swift and Metal | Redoes the port and its verification against the reference; the Rust engine already runs on Metal |
| Bake LUTs and apply them with Core Image | Fast, but loses the spatial effects (grain, halation, couplers) that make the result film-like |
| Call the upstream command-line tool as a subprocess | No interactive preview, awkward in a sandboxed app |

## Consequences

- The project is GPLv3, like the engine, so it cannot be distributed through the Mac App Store.
- Building needs Rust; the engine is compiled once into an XCFramework by `scripts/build-engine.sh`.
- Updating the engine is moving the submodule pointer and running the tests. The pipeline cache key in
  the bridge mirrors a function of the upstream GUI and must be kept in sync with it.
