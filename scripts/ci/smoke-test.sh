#!/usr/bin/env bash
# CI smoke test: opens a generated test chart in the built app, checks that the
# app stays up, and saves a screenshot to build/smoke/ for inspection.
#
# Usage: scripts/ci/smoke-test.sh [path/to/Alteralux.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${1:-$ROOT/build/DerivedData/Build/Products/Release/Alteralux.app}"
# `open -a` needs an absolute path.
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
OUT="$ROOT/build/smoke"
mkdir -p "$OUT"

echo "==> Drawing the test chart"
swift "$ROOT/scripts/ci/make-test-chart.swift" "$OUT/chart.png"

echo "==> Launching $(basename "$APP")"
open -a "$APP" "$OUT/chart.png"
for _ in $(seq 1 30); do
  pgrep -x Alteralux >/dev/null && break
  sleep 1
done

# Time for the engine to start and the first preview to render.
sleep 25

if ! pgrep -x Alteralux >/dev/null; then
  echo "The app is not running: it failed to launch or crashed." >&2
  ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i alteralux || true
  exit 1
fi

echo "==> Taking a screenshot"
screencapture -x "$OUT/screenshot.png" || echo "screencapture failed (no screen access?)"

osascript -e 'tell application "Alteralux" to quit' 2>/dev/null || pkill -x Alteralux || true
ls -la "$OUT"
