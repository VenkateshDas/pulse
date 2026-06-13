#!/bin/bash
# Create a distributable DMG from dist/Pulse.app.
# Usage: scripts/dmg.sh [version]   (default: reads CFBundleShortVersionString)
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Pulse.app"

if [ ! -d "$APP" ]; then
    echo "No dist/Pulse.app found. Run 'make bundle' first."
    exit 1
fi

# Version from arg or Info.plist
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(defaults read "$(pwd)/$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")
fi

DMG_NAME="Pulse-${VERSION}.dmg"
DMG_OUT="dist/$DMG_NAME"
TMP_DIR="dist/.dmg-staging"

rm -rf "$TMP_DIR" "$DMG_OUT"
mkdir -p "$TMP_DIR"

# Copy app + symlink to /Applications for drag-install UX
cp -R "$APP" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

# Create compressed read-only DMG
hdiutil create \
    -volname "Pulse $VERSION" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUT"

rm -rf "$TMP_DIR"

echo ""
echo "DMG ready: $DMG_OUT"
echo ""
echo "NOTE: Ad-hoc signed — Gatekeeper will block on other Macs."
echo "Tell friends to right-click Pulse.app → Open (first launch only)."
echo "Or they can run: xattr -dr com.apple.quarantine /Applications/Pulse.app"
