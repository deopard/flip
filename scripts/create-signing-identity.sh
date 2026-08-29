#!/bin/bash
# Creates the self-signed certificate that scripts/build.sh and scripts/release.sh sign with.
#
# Why it matters, beyond convenience: macOS identifies a signed app by its designated
# requirement. Ad-hoc signing (`codesign -s -`) makes that the binary's own hash, so every
# build is a different app, and the Accessibility permission a user granted does not carry over
# to the next version. The old entry stays in the list looking switched on while the new build
# has none, which is close to undiagnosable from the outside. Signing with a fixed certificate
# makes the requirement `identifier "video.cutback.flip" and certificate leaf = H"..."`, which
# does not change between builds. Keychain access stops re-prompting for the same reason.
#
# The certificate travels inside the signature, so people installing a release need nothing.
# This is not notarization and does not get past Gatekeeper: see the README.
#
# The certificate lives in its own keychain, not your login keychain, so this needs no password
# and cannot touch anything else. The keychain password below is deliberately not a secret: it
# protects a self-signed certificate that grants no authority beyond naming this app.
#
#   ./scripts/create-signing-identity.sh              create it
#   ./scripts/create-signing-identity.sh --export F   back it up to F.p12, keep that private
#   ./scripts/create-signing-identity.sh --import F   restore it from F.p12 on another machine
#   ./scripts/create-signing-identity.sh --remove     delete it; builds fall back to ad hoc
set -euo pipefail

NAME="Flip Signing"
KEYCHAIN="$HOME/Library/Keychains/flip-signing.keychain-db"
KEYCHAIN_PASSWORD="flip-signing"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_FILE="$ROOT/scripts/.signing-identity"
LEGACY_ALGS=(-macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES)

drop_from_search_list() {
    local current
    current=$(security list-keychains -d user | sed 's/[" ]//g' | grep -v "flip-signing" || true)
    # shellcheck disable=SC2086
    security list-keychains -d user -s $current >/dev/null 2>&1 || true
}

add_to_search_list() {
    local current
    current=$(security list-keychains -d user | sed 's/[" ]//g' | grep -v "flip-signing" || true)
    # shellcheck disable=SC2086
    security list-keychains -d user -s $current "$KEYCHAIN"
}

record_identity() {
    local hash
    hash=$(security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" | head -1 | awk '{print $2}')
    if [[ -z "$hash" ]]; then
        echo "Failed: no code signing identity came back from the keychain." >&2
        exit 1
    fi
    printf '%s\n' "$hash" > "$IDENTITY_FILE"
    echo "Identity $hash (\"$NAME\")."
}

case "${1:-}" in
--remove)
    drop_from_search_list
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    rm -f "$IDENTITY_FILE"
    echo "Removed. Builds fall back to ad hoc signing."
    exit 0
    ;;
--export)
    OUT="${2:?usage: --export <path without extension>}"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$KEYCHAIN_PASSWORD" -o "$OUT.p12"
    chmod 600 "$OUT.p12"
    echo "Wrote $OUT.p12 (passphrase: $KEYCHAIN_PASSWORD)."
    echo "Keep it somewhere private. Losing it means the next release is a different app to"
    echo "macOS, and everyone has to grant Accessibility again."
    exit 0
    ;;
--import)
    IN="${2:?usage: --import <path without extension>}"
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security import "$IN.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASSWORD" \
        -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1
    add_to_search_list
    record_identity
    exit 0
    ;;
esac

# The identity file is not in version control, so a fresh clone will not have it. Never take
# its absence as licence to mint a new certificate: that would change the app's identity and
# put every existing user back to granting Accessibility again. Only the keychain is authority.
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$NAME"; then
    add_to_search_list
    record_identity
    echo "Already set up; recorded the existing identity."
    exit 0
fi

WORK="$(mktemp -d /private/tmp/flip-signing.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

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
    -passout pass:"$KEYCHAIN_PASSWORD" "${LEGACY_ALGS[@]}" 2>/dev/null

echo "Creating a dedicated keychain for it..."
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" \
    -P "$KEYCHAIN_PASSWORD" -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Without this codesign is refused the private key and fails with errSecInternalComponent.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1

add_to_search_list
record_identity

echo
echo "Back it up before you ship anything with it:"
echo "  ./scripts/create-signing-identity.sh --export ~/somewhere-private/flip-signing"
