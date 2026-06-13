#!/bin/bash
# Build a release binary and wrap it in a minimal Pulse.app bundle.
# Usage: scripts/bundle.sh [output-dir]   (default: ./dist)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-dist}"
APP="$OUT/Pulse.app"

# See Makefile: patched ManifestAPI works around a broken CLT 26.5 install.
export SWIFTPM_CUSTOM_LIBS_DIR="$HOME/.local/swiftpm-fix"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Pulse" "$APP/Contents/MacOS/Pulse"
if [ -f "Sources/Pulse/Resources/AppIcon.icns" ]; then
    cp "Sources/Pulse/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <!-- Menu-bar-primary app: no dock icon (mirrors .accessory policy). -->
    <key>LSUIElement</key><true/>
    <!-- TCC pre-flight: shown when Pulse first reads these locations. -->
    <key>NSDesktopFolderUsageDescription</key><string>Pulse scans your Desktop to map large files and find safe-to-clean space.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Pulse scans Documents to map large files and find safe-to-clean space.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Pulse scans Downloads to map large files and find safe-to-clean space.</string>
    <!-- Sparkle auto-update (P0-8): set the appcast URL + public EdDSA key when
         the Sparkle dependency is enabled in Package.swift. -->
    <key>SUFeedURL</key><string>https://pulse.app/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# Signing. Set SIGN_IDENTITY to a Developer ID Application identity for a
# distributable, notarizable build (hardened runtime); otherwise ad-hoc sign
# for local launches only (Gatekeeper blocks ad-hoc apps on other machines).
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with Developer ID: $SIGN_IDENTITY"
    echo "To notarize:"
    echo "  ditto -c -k --keepParent \"$APP\" Pulse.zip"
    echo "  xcrun notarytool submit Pulse.zip --keychain-profile <profile> --wait"
    echo "  xcrun stapler staple \"$APP\""
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed (local launches only — set SIGN_IDENTITY for distribution)."
fi

echo "Built: $APP"
