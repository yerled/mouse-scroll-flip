#!/bin/bash
# Build AppIcon.icns from the generated 1024px PNG. Requires macOS sips + iconutil.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-"$ROOT/dist/AppIcon.icns"}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$ROOT/scripts/render_icon.py" "$TMP/icon_1024.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$TMP/icon_1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$TMP/icon_1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$TMP/icon_1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$TMP/icon_1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$TMP/icon_1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$TMP/icon_1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$TMP/icon_1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$TMP/icon_1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$TMP/icon_1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$TMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
