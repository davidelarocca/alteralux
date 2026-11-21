#!/usr/bin/env bash
# Copies lensfun's lens database into third_party/lensfun, unmodified.
#
# Usage: scripts/update-lensfun.sh <commit of github.com/lensfun/lensfun>
#
# The database is licensed CC BY-SA 3.0, not GPL: it is kept as separate files
# with its license and read by the app at run time (see third_party/lensfun/README.md).
# Only the database's XML files and its license are taken; nothing from the
# archive is run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT="${1:?usage: scripts/update-lensfun.sh <lensfun commit>}"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Give the full 40-character commit." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL -o "$WORK/lensfun.tar.gz" "https://codeload.github.com/lensfun/lensfun/tar.gz/$COMMIT"
mkdir "$WORK/src"
tar -xzf "$WORK/lensfun.tar.gz" -C "$WORK/src" --strip-components 1 \
  "lensfun-$COMMIT/data/db" "lensfun-$COMMIT/data/COPYING.CC_BY-SA_3.0"

DEST="$ROOT/third_party/lensfun"
rm -rf "$DEST/db"
mkdir -p "$DEST/db"
cp "$WORK/src/data/db/"*.xml "$DEST/db/"
cp "$WORK/src/data/COPYING.CC_BY-SA_3.0" "$DEST/COPYING.CC_BY-SA_3.0"
echo "$COMMIT" > "$DEST/COMMIT"
echo "lensfun database at $COMMIT: $(ls "$DEST/db" | wc -l | tr -d ' ') files in third_party/lensfun/db"
