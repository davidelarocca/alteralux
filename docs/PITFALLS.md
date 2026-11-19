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
- **Strings in package views are looked up in the app's string catalog.** A new string in `SpektrafilmUI`
  or `DesignSystem` needs its entry in `apple/Spektrafilm/Resources/Localizable.xcstrings`, or it shows in
  English only.

## Data and tests

- UI tests must never open the user's real data: they launch with the isolation arguments in `uiTests.isolation` (the tests rule of the setup says how).
- **Tests of the Swift packages use the real engine and the submodule's data.** They need the submodule
  checked out (`git submodule update --init`) and the engine built.
- **Tests write only to the temporary folder.** The test charts are generated there and removed.

## UI

- **The window follows the system appearance unless told otherwise.** With a dark viewer and a light
  system the title was unreadable and the photo strip white. The app sets the dark appearance at launch.
- **`Text("a") vs Text(condition ? "a" : "b")`.** A ternary of string literals resolves to `String`, which
  is not localized. Build two `Text` values instead.
