#!/bin/bash
# Create a stable, self-signed code-signing identity for LOCAL dev builds.
#
# Why: `make bundle` ad-hoc signs, which gives the binary a new code hash on
# every build. macOS TCC keys permission grants (Full Disk Access, App
# Management) to that hash, so each rebuild silently invalidates anything you
# granted — making permission-gated features (e.g. the App Uninstaller, which
# must move other apps' bundles to the Trash) impossible to test reliably.
#
# A self-signed identity has a STABLE designated requirement, so a grant made
# once persists across rebuilds. Run this ONCE; `make bundle` picks it up.
set -euo pipefail

IDENTITY="Pulse Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Identity \"$IDENTITY\" already exists — nothing to do."
    exit 0
fi

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

cat > "$DIR/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# Self-signed cert + key. PKCS#12 uses legacy PBE so macOS `security import`
# (which rejects LibreSSL's modern default) can read it.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
    -days 3650 -config "$DIR/cfg" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -out "$DIR/id.p12" \
    -passout pass:pulse -name "$IDENTITY" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

echo "Importing \"$IDENTITY\" into your login keychain…"
# -A lets codesign use the key without a per-build password prompt.
security import "$DIR/id.p12" -k "$KEYCHAIN" -P pulse -T /usr/bin/codesign -A

echo "Trusting it for code signing (you may be asked for your login password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$DIR/cert.pem"

echo
echo "Done — \"$IDENTITY\" is ready."
echo "Next:"
echo "  make bundle && open dist/Pulse.app"
echo "  Grant Pulse Full Disk Access ONCE (System Settings → Privacy & Security)."
echo "  The grant now survives rebuilds, so Uninstall can move apps + leftovers."
