#!/bin/bash
# Creates a self-signed code signing certificate that scripts/build.sh signs every build with.
#
# Why this exists: `codesign -s -` (ad hoc) produces a different signature on every build.
# macOS ties the Accessibility permission and Keychain access to that signature, so each
# rebuild looks like a brand new app and re-asks for both. A fixed certificate makes the
# signature stable and both prompts stop.
#
# The certificate lives in its own keychain, not your login keychain, so this needs no
# password and cannot touch anything else. The keychain password below is deliberately not a
# secret: it protects a self-signed development certificate that grants no authority.
#
# Local development only. It does NOT make the app distributable to other people; see the
# README section "Giving it to other people".
#
# To undo: ./scripts/create-signing-identity.sh --remove
set -euo pipefail

NAME="Flip Dev"
KEYCHAIN="$HOME/Library/Keychains/flip-signing.keychain-db"
KEYCHAIN_SHORT="flip-signing.keychain"
KEYCHAIN_PASSWORD="flip-dev-signing"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_FILE="$ROOT/scripts/.signing-identity"

remove_from_search_list() {
    local current
    current=$(security list-keychains -d user | sed 's/[" ]//g' | grep -v "flip-signing" || true)
    # shellcheck disable=SC2086
    security list-keychains -d user -s $current >/dev/null 2>&1 || true
}

if [[ "${1:-}" == "--remove" ]]; then
    remove_from_search_list
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    rm -f "$IDENTITY_FILE"
    echo "Removed the \"$NAME\" signing keychain. Builds fall back to ad hoc signing."
    exit 0
fi

if [[ -f "$IDENTITY_FILE" ]] && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$NAME"; then
    echo "\"$NAME\" already set up. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d /private/tmp/flip-signing.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = Flip Dev

[ ext ]
basicConstraints = critical,CA:false
keyUsage         = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

echo "Generating a 10 year self-signed code signing certificate..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

# OpenSSL 3 defaults to a PKCS12 MAC that macOS cannot verify, hence the legacy algorithms.
openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -passout pass:"$KEYCHAIN_PASSWORD" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

echo "Creating a dedicated keychain for it..."
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # no auto lock, no timeout
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

security import "$WORK/identity.p12" -k "$KEYCHAIN" \
    -P "$KEYCHAIN_PASSWORD" -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Without this codesign is refused the private key and fails with errSecInternalComponent.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1

# codesign only searches the user's keychain list.
CURRENT=$(security list-keychains -d user | sed 's/[" ]//g' | grep -v "flip-signing" || true)
# shellcheck disable=SC2086
security list-keychains -d user -s $CURRENT "$KEYCHAIN"

HASH=$(security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" | head -1 | awk '{print $2}')
if [[ -z "$HASH" ]]; then
    echo "Failed: the certificate was created but no code signing identity came back." >&2
    exit 1
fi
printf '%s\n' "$HASH" > "$IDENTITY_FILE"

echo
echo "Done. Identity $HASH (\"$NAME\")."
echo "scripts/build.sh will sign with it from now on."
echo
echo "Next: run ./scripts/build.sh, then turn Flip off and on once more in"
echo "System Settings > Privacy & Security > Accessibility. That is the last time."
