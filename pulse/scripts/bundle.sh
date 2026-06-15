#!/bin/bash
# Build a release binary and wrap it in a minimal Pulse.app bundle.
# Usage: scripts/bundle.sh [output-dir]   (default: ./dist)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-dist}"
APP="$OUT/Pulse.app"

# Version stamped into the bundle. CD passes PULSE_VERSION (derived from the
# git tag) so the app's About box matches the release; local builds default.
VERSION="${PULSE_VERSION:-0.1.0}"

# See Makefile: patched ManifestAPI works around a broken CLT 26.5 install.
# Only applied when the patched dir exists (local dev) — CI runners have a
# healthy toolchain and must not point SwiftPM at a missing libs dir.
FIX_DIR="$HOME/.local/swiftpm-fix"
if [ -d "$FIX_DIR/ManifestAPI" ]; then
    export SWIFTPM_CUSTOM_LIBS_DIR="$FIX_DIR"
fi
# Architecture selection. Default is a native single-arch build, which works
# with a Command Line Tools-only toolchain (local dev). Multi-arch (universal)
# builds go through SwiftPM's Xcode build system and need full Xcode + xcbuild,
# so CD opts in by exporting PULSE_ARCHS="arm64 x86_64" to ship a DMG that runs
# on both Apple Silicon and Intel Macs.
ARCH_FLAGS=""
for a in ${PULSE_ARCHS:-}; do ARCH_FLAGS="$ARCH_FLAGS --arch $a"; done
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS

# Multi-arch SwiftPM emits to .build/apple/Products/Release; a plain native
# build lands in .build/release. Pick whichever exists.
BIN=""
for candidate in ".build/apple/Products/Release/Pulse" ".build/release/Pulse"; do
    if [ -f "$candidate" ]; then BIN="$candidate"; break; fi
done
[ -n "$BIN" ] || { echo "error: built Pulse binary not found"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pulse"
echo "Bundled binary architectures: $(lipo -archs "$APP/Contents/MacOS/Pulse" 2>/dev/null || echo unknown)"
if [ -f "Sources/Pulse/Resources/AppIcon.icns" ]; then
    cp "Sources/Pulse/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Pulse</string>
    <key>CFBundleIdentifier</key><string>com.pulse.app</string>
    <key>CFBundleName</key><string>Pulse</string>
    <key>CFBundleDisplayName</key><string>Pulse</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <!-- Regular app: shows in dock and responds to Cmd+Tab. -->
    <key>LSUIElement</key><false/>
    <!-- TCC pre-flight: shown when Pulse first reads these locations. -->
    <key>NSDesktopFolderUsageDescription</key><string>Pulse scans your Desktop to map large files and find safe-to-clean space.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Pulse scans Documents to map large files and find safe-to-clean space.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Pulse scans Downloads to map large files and find safe-to-clean space.</string>
    <!-- Uninstaller: ask Finder to move protected (App Store / App-Management)
         bundles to the Trash via Apple Events. -->
    <key>NSAppleEventsUsageDescription</key><string>Pulse asks Finder to move an app you’re uninstalling to the Trash.</string>
    <!-- Sparkle auto-update (P0-8): disabled until a real appcast is hosted.
         Before enabling, host appcast.xml (e.g. via GitHub Releases/Pages),
         set SUFeedURL + SUPublicEDKey, flip SUEnableAutomaticChecks to true,
         and add the Sparkle dependency in Package.swift. The previous default
         pointed at an unowned domain — left off so no build phones it home. -->
    <key>SUEnableAutomaticChecks</key><false/>
</dict>
</plist>
PLIST

# Signing. Set SIGN_IDENTITY to a Developer ID Application identity for a
# distributable, notarizable build (hardened runtime); otherwise ad-hoc sign
# for local launches only (Gatekeeper blocks ad-hoc apps on other machines).
DEV_IDENTITY="Pulse Local Signing"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with Developer ID: $SIGN_IDENTITY"
    echo "To notarize:"
    echo "  ditto -c -k --keepParent \"$APP\" Pulse.zip"
    echo "  xcrun notarytool submit Pulse.zip --keychain-profile <profile> --wait"
    echo "  xcrun stapler staple \"$APP\""
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_IDENTITY"; then
    # Stable local identity: TCC grants (Full Disk Access / App Management)
    # persist across rebuilds, so permission-gated features stay testable.
    codesign --force --sign "$DEV_IDENTITY" "$APP"
    echo "Signed with local dev identity \"$DEV_IDENTITY\" — TCC grants persist across rebuilds."
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed (local launches only — set SIGN_IDENTITY for distribution)."
    echo "NOTE: ad-hoc builds get a new code hash each rebuild, which RESETS any"
    echo "      Full Disk Access / App Management grant. Run 'make dev-cert' once"
    echo "      for a stable identity so Uninstall (and other gated features) work."
fi

echo "Built: $APP"
