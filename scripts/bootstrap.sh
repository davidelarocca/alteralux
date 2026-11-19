#!/usr/bin/env bash
# One-step setup on a Mac: builds the engine and generates the Xcode project.
#
# Usage: scripts/bootstrap.sh [--universal] [--debug] [--skip-engine]
#   --skip-engine  only regenerate the Xcode project (engine already built)
#   other options are passed to scripts/build-engine.sh
#
# Afterwards open apple/Spektrafilm.xcodeproj and press Run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# XcodeGen turns apple/project.yml into the Xcode project. A pinned release is
# downloaded into build/tools, so nothing is installed system-wide.
XCODEGEN_VERSION="2.48.0"
XCODEGEN_SHA256="620c9f0dc10849f94728ab5df52d225ebab8187439dd6fee1925e59e80dff892"

SKIP_ENGINE=0
ENGINE_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --skip-engine) SKIP_ENGINE=1 ;;
    *) ENGINE_ARGS+=("$arg") ;;
  esac
done

[[ "$(uname)" == "Darwin" ]] || { echo "This script must run on macOS." >&2; exit 1; }

if [[ $SKIP_ENGINE == 0 ]]; then
  "$ROOT/scripts/build-engine.sh" ${ENGINE_ARGS[@]+"${ENGINE_ARGS[@]}"}
fi

TOOLS="$ROOT/build/tools"
XCODEGEN="$TOOLS/xcodegen-$XCODEGEN_VERSION/xcodegen/bin/xcodegen"
if [[ ! -x "$XCODEGEN" ]]; then
  echo "==> Downloading XcodeGen $XCODEGEN_VERSION"
  mkdir -p "$TOOLS/xcodegen-$XCODEGEN_VERSION"
  ARCHIVE="$TOOLS/xcodegen-$XCODEGEN_VERSION.zip"
  curl -fsSL -o "$ARCHIVE" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
  echo "$XCODEGEN_SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null \
    || { echo "XcodeGen download does not match its expected checksum." >&2; exit 1; }
  unzip -q -o "$ARCHIVE" -d "$TOOLS/xcodegen-$XCODEGEN_VERSION"
  rm "$ARCHIVE"
fi

echo "==> Generating apple/Spektrafilm.xcodeproj"
"$XCODEGEN" generate --quiet --spec "$ROOT/apple/project.yml" --project "$ROOT/apple"

echo "==> Done. Open the project with:"
echo "    open apple/Spektrafilm.xcodeproj"
