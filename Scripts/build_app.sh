#!/bin/bash
# Builds a universal PeekBar.app into dist/ and ad-hoc signs it with the hardened runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DIST="$ROOT/dist"
APP="$DIST/PeekBar.app"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCHES="${ARCHES:---arch arm64 --arch x86_64}"

echo "==> Building release ($ARCHES)"
# shellcheck disable=SC2086
swift build -c release $ARCHES --product PeekBar 2>&1 | grep -E "error:|warning: unre" || true
BIN_CHECK="$(swift build -c release $ARCHES --product PeekBar --show-bin-path)/PeekBar"
swift build -c release $ARCHES --product PeekBar >/dev/null 2>&1 || { echo "BUILD FAILED"; exit 1; }
BIN="$(swift build -c release $ARCHES --product PeekBar --show-bin-path)/PeekBar"
test -x "$BIN"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PeekBar"
sed "s/__BUILD__/$BUILD_NUMBER/" Packaging/Info.plist > "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

echo "==> Icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
swiftc -O Packaging/make_icon.swift -o "$DIST/make_icon" 2>/dev/null
"$DIST/make_icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$DIST/make_icon"

echo "==> Signing"
# A stable identity keeps Screen Recording / Accessibility grants across rebuilds (SRS §11).
# Priority: SIGN_IDENTITY env (Developer ID etc.) > the local self-signed identity in
# Packaging/PeekBar-signing.keychain-db > ad hoc (permissions reset on every rebuild).
LOCAL_KC="$ROOT/Packaging/PeekBar-signing.keychain-db"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  case "$SIGN_IDENTITY" in
    *"Developer ID"*) codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP" ;;
    *) codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP" ;;
  esac
  echo "    signed with: $SIGN_IDENTITY"
elif [ -f "$LOCAL_KC" ] && security unlock-keychain -p peekbar "$LOCAL_KC" 2>/dev/null \
     && security find-identity -v -p codesigning "$LOCAL_KC" | grep -q "PeekBar Local Signing"; then
  # codesign only finds identities in the user's keychain search list; add ours once.
  if ! security list-keychains -d user | grep -q "PeekBar-signing.keychain-db"; then
    CURRENT=$(security list-keychains -d user | sed -E 's/^ *"(.*)"$/\1/')
    # shellcheck disable=SC2086
    security list-keychains -d user -s $CURRENT "$LOCAL_KC"
  fi
  codesign --force --options runtime --sign "PeekBar Local Signing" "$APP"
  echo "    signed with: PeekBar Local Signing (local self-signed identity)"
else
  codesign --force --options runtime --sign - "$APP"
  echo "    signed ad hoc (permissions reset on every rebuild)"
fi
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/PeekBar"
echo "==> Built $APP (build $BUILD_NUMBER)"
