#!/bin/bash
# Builds a release archive for other people to download.
#
# Differences from scripts/build.sh, which builds for this machine:
#  - universal, so it runs on Apple Silicon and Intel
#
# It signs with the project certificate from scripts/create-signing-identity.sh. That is not
# cosmetic: an ad-hoc signature's identity is the binary's own hash, so every release would be a
# different app to macOS and nobody's Accessibility permission would survive an update. A fixed
# certificate keeps the identity stable across versions. The certificate travels inside the
# signature, so people installing this need nothing.
#
# The result is still not notarized: see the README, "Giving it to other people". Anyone who
# downloads it has to clear the quarantine flag once.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Flip.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ARCHIVE="$BUILD/Flip-$VERSION-macos-universal.zip"

rm -rf "$APP" "$ARCHIVE" "$BUILD/arch"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/arch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then "$ROOT/scripts/make-icon.sh"; fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

for ARCH in arm64 x86_64; do
  echo "Compiling $ARCH..."
  swiftc \
    -swift-version 5 \
    -target "$ARCH-apple-macos14.0" \
    -O \
    -framework AppKit -framework SwiftUI -framework Carbon \
    -framework ApplicationServices -framework Security \
    -o "$BUILD/arch/Flip-$ARCH" \
    "$ROOT"/Sources/Flip/*.swift
done

echo "Merging into a universal binary..."
lipo -create -output "$APP/Contents/MacOS/Flip" "$BUILD/arch/Flip-arm64" "$BUILD/arch/Flip-x86_64"
rm -rf "$BUILD/arch"
lipo -info "$APP/Contents/MacOS/Flip"

IDENTITY_FILE="$ROOT/scripts/.signing-identity"
if [ -f "$IDENTITY_FILE" ]; then
  echo "Signing with the project certificate..."
  codesign --force --deep --sign "$(cat "$IDENTITY_FILE")" "$APP"
else
  echo "WARNING: no project certificate, signing ad hoc." >&2
  echo "         Everyone who installs this will have to grant Accessibility again," >&2
  echo "         because an ad-hoc signature's identity is the binary's hash." >&2
  echo "         Run ./scripts/create-signing-identity.sh first." >&2
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --strict "$APP" && echo "signature verifies"
echo "identity macOS will remember:"
codesign -d -r- "$APP" 2>&1 | tail -1 | sed 's/^/  /'

echo "Archiving..."
# ditto, not zip: it preserves the signature and the bundle's extended attributes.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo
echo "$ARCHIVE"
ls -lh "$ARCHIVE" | awk '{print "  " $5}'
shasum -a 256 "$ARCHIVE" | awk '{print "  sha256 " $1}'
