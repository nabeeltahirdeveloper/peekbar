#!/bin/bash
# Wraps dist/PeekBar.app in a compressed DMG with an Applications shortcut.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/PeekBar.app"
test -d "$APP" || { echo "Run Scripts/build_app.sh first"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/PeekBar-$VERSION.dmg"
STAGE="$DIST/dmg-root"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<TXT
PeekBar $VERSION

1. Drag PeekBar into Applications.
2. Requires macOS 12 Monterey or later, Apple Silicon or Intel.
3. This build is signed with a local certificate, not an Apple Developer ID, so on a new
   Mac the first launch needs: right-click PeekBar.app -> Open -> Open.
   If macOS says the app is damaged, run in Terminal:
     xattr -dr com.apple.quarantine /Applications/PeekBar.app
4. Grant Screen Recording (tile icons) and Accessibility (clicking extras) when asked.
5. Quit other menu-bar hiding tools (Hidden Bar, MenubarHide, Ice, Bartender) first;
   two separators fight each other.

Privacy: PeekBar captures only menu-bar icons, uses Accessibility only to click them,
and never saves or sends anything.
TXT
hdiutil create -volname "PeekBar $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"
if [ -n "${SIGN_IDENTITY:-}" ]; then codesign --sign "$SIGN_IDENTITY" "$DMG"; fi
hdiutil verify "$DMG" >/dev/null
ls -la "$DMG"
