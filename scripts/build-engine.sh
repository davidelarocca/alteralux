#!/usr/bin/env bash
# Builds the Rust engine for macOS and packages it for Swift:
#   apple/SpektrafilmKit/Frameworks/spektrafilm_ffiFFI.xcframework
#   apple/SpektrafilmKit/Sources/SpektrafilmEngine/Generated/spektrafilm_ffi.swift
#
# Usage: scripts/build-engine.sh [--universal] [--debug]
#   --universal  also build for Intel Macs (x86_64) and merge with lipo
#   --debug      unoptimized engine (much slower renders; for debugging only)
#
# Requirements: Xcode (command line tools) and Rust via rustup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT/engine"
KIT="$ROOT/apple/SpektrafilmKit"
BUILD="$ROOT/build/engine"
CRATE_LIB="spektrafilm_ffi"
MODULE="${CRATE_LIB}FFI"

UNIVERSAL=0
PROFILE="release"
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --debug) PROFILE="debug" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ "$(uname)" == "Darwin" ]] || { echo "This script must run on macOS." >&2; exit 1; }
command -v cargo >/dev/null || { echo "Rust not found: install it from https://rustup.rs" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild not found: install Xcode." >&2; exit 1; }

if [[ ! -f "$ENGINE/vendor/spektrafilm-rs/Cargo.toml" ]]; then
  echo "==> Fetching the spektrafilm-rs submodule"
  git -C "$ROOT" submodule update --init --recursive
fi

# Linked git worktrees reuse the main checkout's Cargo target folder, so a new
# worktree compiles only what differs instead of the whole engine.
if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  COMMON_GIT_DIR="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  MAIN_CHECKOUT="${COMMON_GIT_DIR%/.git}"
  if [[ "$COMMON_GIT_DIR" == */.git && "$MAIN_CHECKOUT" != "$ROOT" && -d "$MAIN_CHECKOUT/engine" ]]; then
    export CARGO_TARGET_DIR="$MAIN_CHECKOUT/engine/target"
  fi
fi
TARGET_DIR="${CARGO_TARGET_DIR:-$ENGINE/target}"

TARGETS=(aarch64-apple-darwin)
[[ $UNIVERSAL == 1 ]] && TARGETS+=(x86_64-apple-darwin)
rustup target add "${TARGETS[@]}" >/dev/null

CARGO_FLAGS=(--manifest-path "$ENGINE/Cargo.toml" -p spektrafilm-ffi)
[[ $PROFILE == release ]] && CARGO_FLAGS+=(--release)
# Match the deployment target of the Swift package.
export MACOSX_DEPLOYMENT_TARGET=26.0

for target in "${TARGETS[@]}"; do
  echo "==> Building engine for $target ($PROFILE)"
  cargo build "${CARGO_FLAGS[@]}" --target "$target"
done

rm -rf "$BUILD"
mkdir -p "$BUILD/headers" "$BUILD/generated"

STATIC_LIB="$BUILD/lib${CRATE_LIB}.a"
if [[ $UNIVERSAL == 1 ]]; then
  lipo -create \
    "$TARGET_DIR/aarch64-apple-darwin/$PROFILE/lib${CRATE_LIB}.a" \
    "$TARGET_DIR/x86_64-apple-darwin/$PROFILE/lib${CRATE_LIB}.a" \
    -output "$STATIC_LIB"
else
  cp "$TARGET_DIR/aarch64-apple-darwin/$PROFILE/lib${CRATE_LIB}.a" "$STATIC_LIB"
fi

echo "==> Generating Swift bindings"
# uniffi-bindgen runs `cargo metadata`, so it must start inside the workspace.
(cd "$ENGINE" && cargo run --quiet --release -p uniffi-bindgen -- \
  generate \
  --library "$TARGET_DIR/aarch64-apple-darwin/$PROFILE/lib${CRATE_LIB}.dylib" \
  --language swift \
  --out-dir "$BUILD/generated")

cp "$BUILD/generated/${MODULE}.h" "$BUILD/headers/"
cp "$BUILD/generated/${MODULE}.modulemap" "$BUILD/headers/module.modulemap"

echo "==> Packaging ${MODULE}.xcframework"
mkdir -p "$KIT/Frameworks" "$KIT/Sources/SpektrafilmEngine/Generated"
rm -rf "$KIT/Frameworks/${MODULE}.xcframework"
xcodebuild -create-xcframework \
  -library "$STATIC_LIB" \
  -headers "$BUILD/headers" \
  -output "$KIT/Frameworks/${MODULE}.xcframework" >/dev/null
cp "$BUILD/generated/${CRATE_LIB}.swift" "$KIT/Sources/SpektrafilmEngine/Generated/"

echo "==> Done"
echo "    $KIT/Frameworks/${MODULE}.xcframework"
echo "    $KIT/Sources/SpektrafilmEngine/Generated/${CRATE_LIB}.swift"
echo "Run the Swift tests with:  swift test --package-path apple/SpektrafilmKit"
