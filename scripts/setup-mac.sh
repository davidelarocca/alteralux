#!/usr/bin/env bash
# First-time setup of a development checkout on a Mac.
#
# Checks the tools the project needs, then builds the Rust engine and generates
# the Xcode project (scripts/bootstrap.sh). Safe to run again at any time.
#
# Usage: scripts/setup-mac.sh [--install]
#   --install  install what is missing instead of only reporting it:
#              Rust through rustup, and jq, SwiftLint and SwiftFormat through
#              Homebrew (when Homebrew is there). Xcode is never installed by
#              this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ "$(uname)" == "Darwin" ]] || { echo "This script must run on macOS." >&2; exit 1; }

missing=0
ok() { printf '  ok       %s\n' "$1"; }
bad() { printf '  MISSING  %s\n           %s\n' "$1" "$2"; missing=1; }
note() { printf '  note     %s\n' "$1"; }

echo "==> Checking the tools"

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$macos_major" -ge 26 ]]; then
  ok "macOS $(sw_vers -productVersion)"
else
  bad "macOS 26 or later (this Mac runs $(sw_vers -productVersion))" "Update macOS: the app needs macOS 26."
fi

if xcodebuild -version >/dev/null 2>&1; then
  ok "$(xcodebuild -version | head -1)"
else
  bad "Xcode" "Install Xcode from the App Store, open it once, then run: sudo xcode-select -s /Applications/Xcode.app"
fi

# Rust installs into ~/.cargo/bin, which a fresh shell may not have on its PATH yet.
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
if ! command -v cargo >/dev/null 2>&1 && [[ $INSTALL == 1 ]]; then
  echo "==> Installing Rust (rustup)"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  . "$HOME/.cargo/env"
fi
if command -v cargo >/dev/null 2>&1; then
  ok "$(cargo --version)"
else
  bad "Rust" "Install it from https://rustup.rs, or run this script with --install."
fi

# Used by the swift-harness checks and by the formatter and linter of the project.
brew_tools=(jq swiftlint swiftformat)
to_install=()
for tool in "${brew_tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || to_install+=("$tool")
done
if [[ ${#to_install[@]} -gt 0 && $INSTALL == 1 ]] && command -v brew >/dev/null 2>&1; then
  echo "==> Installing ${to_install[*]} (Homebrew)"
  brew install "${to_install[@]}"
fi
for tool in "${brew_tools[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  elif command -v brew >/dev/null 2>&1; then
    bad "$tool" "brew install $tool   (or run this script with --install)"
  else
    bad "$tool" "Install Homebrew from https://brew.sh, then: brew install $tool"
  fi
done

if [[ $missing == 1 ]]; then
  echo
  echo "Install what is missing, then run scripts/setup-mac.sh again."
  exit 1
fi

echo "==> Fetching the engine submodule"
git -C "$ROOT" submodule update --init --recursive

"$ROOT/scripts/bootstrap.sh"

cat <<'EOF'

==> Ready.

  Open the app in Xcode and press Run:
      open apple/Spektrafilm.xcodeproj

  Check everything from the command line:
      scripts/verify.sh fast

  With Claude Code, install the swift-harness plugin once, then approve the
  verify command so the end-of-turn check can run it:
      /plugin marketplace add davidelarocca/swift-harness
      /plugin install swift-harness@swift-harness
      /swift-harness:approve-verify
      /swift-harness:doctor

  What is done and what comes next: docs/ROADMAP.md
EOF
