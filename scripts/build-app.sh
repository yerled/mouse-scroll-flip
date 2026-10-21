#!/bin/bash
# Build a universal (arm64 + x86_64) Mouse Scroll Flip.app, then zip and dmg it.
# Ad-hoc signed. No Apple Developer certificate required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  VERSION="${GITHUB_REF#refs/tags/v}"
fi
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"

export MACOSX_DEPLOYMENT_TARGET=13.0

DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

build_arch() {
  local arch="$1"
  local triple="${arch}-apple-macosx13.0"
  echo "Building $triple" >&2
  # Compiler chatter stays on stderr so the captured path is only the binary.
  swift build -c release --triple "$triple" --product MouseScrollFlip >&2
  local bin_dir
  bin_dir="$(swift build -c release --triple "$triple" --product MouseScrollFlip --show-bin-path 2>/dev/null | tail -n 1)"
  local bin="$bin_dir/MouseScrollFlip"
  if [[ ! -x "$bin" ]]; then
    echo "Missing binary at $bin" >&2
    exit 1
  fi
  printf '%s\n' "$bin"
}

ARM="$(build_arch arm64)" || exit 1
X64="$(build_arch x86_64)" || exit 1
UNIVERSAL="$DIST/MouseScrollFlip"
lipo -create "$ARM" "$X64" -output "$UNIVERSAL"

LIPO_INFO="$(lipo -info "$UNIVERSAL")"
echo "$LIPO_INFO"
if [[ "$LIPO_INFO" != *"arm64"* || "$LIPO_INFO" != *"x86_64"* ]]; then
  echo "Universal binary is missing an architecture: $LIPO_INFO" >&2
  exit 1
fi

MINOS_LINES="$(vtool -show-build "$UNIVERSAL" | awk '/minos/ { print $2 }')"
if [[ -z "$MINOS_LINES" ]]; then
  echo "Binary has no LC_BUILD_VERSION minos" >&2
  vtool -show-build "$UNIVERSAL" >&2 || true
  exit 1
fi
while IFS= read -r minos; do
  major="${minos%%.*}"
  if [[ "$major" != "13" ]]; then
    echo "Expected deployment target macOS 13, found minos $minos" >&2
    exit 1
  fi
done <<< "$MINOS_LINES"

APP_NAME="Mouse Scroll Flip"
APP="$DIST/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$UNIVERSAL" "$APP/Contents/MacOS/MouseScrollFlip"
chmod 755 "$APP/Contents/MacOS/MouseScrollFlip"

sed \
  -e "s/__MARKETING_VERSION__/${VERSION}/g" \
  -e "s/__BUILD_VERSION__/${BUILD_NUMBER}/g" \
  "$ROOT/packaging/Info.plist" > "$APP/Contents/Info.plist"

"$ROOT/scripts/make-icon.sh" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. Hardened runtime is intentionally off: there is no
# Developer ID certificate, and users clear quarantine themselves.
codesign --force --sign - "$APP/Contents/MacOS/MouseScrollFlip"
codesign --force --sign - "$APP"
codesign --verify --verbose=2 "$APP"

STAGE="$DIST/MouseScrollFlip"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp "$ROOT/packaging/OPEN-ME.txt" "$STAGE/OPEN-ME.txt"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"

ZIP="$DIST/MouseScrollFlip-${VERSION}-macOS.zip"
ditto -c -k --keepParent "$STAGE" "$ZIP"

DMG_ROOT="$(mktemp -d)"
trap 'rm -rf "$DMG_ROOT"' EXIT
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
cp "$ROOT/packaging/OPEN-ME.txt" "$DMG_ROOT/OPEN-ME.txt"
cp "$ROOT/LICENSE" "$DMG_ROOT/LICENSE.txt"
ln -s /Applications "$DMG_ROOT/Applications"

DMG="$DIST/MouseScrollFlip-${VERSION}-macOS.dmg"
for attempt in 1 2 3 4 5; do
  if hdiutil create \
    -volname "Mouse Scroll Flip" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG"; then
    break
  fi
  if [[ "$attempt" == "5" ]]; then
    echo "hdiutil failed after 5 attempts" >&2
    exit 1
  fi
  echo "hdiutil failed (attempt ${attempt}), retrying" >&2
  sleep 2
done

echo "App: $APP"
echo "Zip: $ZIP"
echo "Dmg: $DMG"
echo "Version: $VERSION ($BUILD_NUMBER)"
