#!/bin/sh
# Sync the upstream PhotoSuite web frontend (kept 1-to-1 at repo root `src/`)
# into the HarmonyOS entry rawfile dir served by the Web component.
# Generated output: harmony/entry/src/main/resources/rawfile/www (gitignored).
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../../src"
DEST_DIR="$SCRIPT_DIR/../entry/src/main/resources/rawfile"
REPO_ROOT="$SCRIPT_DIR/../.."

if [ ! -f "$SRC_DIR/index.html" ]; then
  echo "sync-www: upstream src/ not found at $SRC_DIR" >&2
  exit 1
fi

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

# Copy the web tree, skipping build-only outputs that must not ship in the HAP.
tar --exclude='wasm/webp-encode/target' --exclude='wasm/*/target' \
  -cf - -C "$SRC_DIR" . | tar -xf - -C "$DEST_DIR"

# Ship the notices/license the Licences dialog reads via read_third_party_notices.
cp "$REPO_ROOT/THIRD-PARTY-NOTICES.md" "$DEST_DIR/THIRD-PARTY-NOTICES.md"
cp "$REPO_ROOT/LICENSE" "$DEST_DIR/LICENSE"

echo "sync-www: $(find "$DEST_DIR" -type f | wc -l | tr -d ' ') files -> $DEST_DIR"
