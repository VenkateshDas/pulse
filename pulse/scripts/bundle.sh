#!/bin/bash
# Build a release binary and wrap it in a minimal Pulse.app bundle.
# Usage: scripts/bundle.sh [output-dir]   (default: ./dist)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-dist}"
APP="$OUT/Pulse.app"

# See Makefile: patched ManifestAPI works around a broken CLT 26.5 install.
# Only applied when the patched dir exists (local dev) — CI runners have a
# healthy toolchain and must not point SwiftPM at a missing libs dir.
FIX_DIR="$HOME/.local/swiftpm-fix"
if [ -d "$FIX_DIR/ManifestAPI" ]; then
    export SWIFTPM_CUSTOM_LIBS_DIR="$FIX_DIR"
fi
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$APP/Contents/Library/LaunchDaemons"
cp ".build/release/Pulse" "$APP/Contents/MacOS/Pulse"
# Privileged helper daemon: the executable lives in MacOS/, named after its
# Mach service, and a LaunchDaemon plist registers it via SMAppService.
HELPER_ID="com.pulse.helper"
cp ".build/release/PulseHelper" "$APP/Contents/MacOS/$HELPER_ID"
if [ -f "Sources/Pulse/Resources/AppIcon.icns" ]; then
    cp "Sources/Pulse/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$HELPER_ID</string>
    <!-- Path is relative to the app bundle; SMAppService resolves it. -->
    <key>BundleProgram</key><string>Contents/MacOS/$HELPER_ID</string>
    <key>MachServices</key>
    <dict><key>$HELPER_ID</key><true/></dict>
    <key>AssociatedBundleIdentifiers</key>
    <array><string>com.pulse.app</string></array>
</dict>
</plist>
PLIST

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
    <!-- Regular app: shows in dock and responds to Cmd+Tab. -->
    <key>LSUIElement</key><false/>
    <!-- TCC pre-flight: shown when Pulse first reads these locations. -->
    <key>NSDesktopFolderUsageDescription</key><string>Pulse scans your Desktop to map large files and find safe-to-clean space.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Pulse scans Documents to map large files and find safe-to-clean space.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Pulse scans Downloads to map large files and find safe-to-clean space.</string>
    <!-- Uninstaller: ask Finder to move protected (App Store / App-Management)
         bundles to the Trash via Apple Events. -->
    <key>NSAppleEventsUsageDescription</key><string>Pulse asks Finder to move an app you’re uninstalling to the Trash.</string>
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
# The privileged helper and the app pin each other by code-signing identifier
# (com.pulse.helper / com.pulse.app), so both must be signed with the SAME
# identity and the nested helper signed BEFORE the enclosing app.
DEV_IDENTITY="Pulse Local Signing"
HELPER_BIN="$APP/Contents/MacOS/$HELPER_ID"

sign_helper_and_app() {
    local identity="$1"; shift
    local extra=("$@")
    # Inner first, with an explicit identifier matching the XPC pin.
    # ${extra[@]+...} keeps `set -u` happy when there are no extra flags.
    codesign --force ${extra[@]+"${extra[@]}"} --identifier "$HELPER_ID" \
        --sign "$identity" "$HELPER_BIN"
    # Then the app bundle (identifier comes from Info.plist: com.pulse.app).
    codesign --force ${extra[@]+"${extra[@]}"} --sign "$identity" "$APP"
}

if [ -n "${SIGN_IDENTITY:-}" ]; then
    sign_helper_and_app "$SIGN_IDENTITY" --options runtime --timestamp
    echo "Signed with Developer ID: $SIGN_IDENTITY"
    echo "To notarize:"
    echo "  ditto -c -k --keepParent \"$APP\" Pulse.zip"
    echo "  xcrun notarytool submit Pulse.zip --keychain-profile <profile> --wait"
    echo "  xcrun stapler staple \"$APP\""
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_IDENTITY"; then
    # Stable local identity: TCC grants (Full Disk Access / App Management)
    # persist across rebuilds, so permission-gated features stay testable.
    sign_helper_and_app "$DEV_IDENTITY"
    echo "Signed with local dev identity \"$DEV_IDENTITY\" — TCC grants persist across rebuilds."
else
    sign_helper_and_app -
    echo "Ad-hoc signed (local launches only — set SIGN_IDENTITY for distribution)."
    echo "NOTE: ad-hoc builds get a new code hash each rebuild, which RESETS any"
    echo "      Full Disk Access / App Management grant, and the privileged helper"
    echo "      (SMAppService) will NOT register. Run 'make dev-cert' once for a"
    echo "      stable identity so Uninstall and the Optimize admin tasks work."
fi

echo "Built: $APP"
