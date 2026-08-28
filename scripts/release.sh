#!/bin/bash
# Builds a release archive for other people to download.
#
# Differences from scripts/build.sh, which builds for this machine:
#  - universal, so it runs on Apple Silicon and Intel
#  - signed ad hoc rather than with the local development certificate, which nobody else has
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

echo "Signing ad hoc..."
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP" && echo "signature verifies"

echo "Archiving..."
# ditto, not zip: it preserves the signature and the bundle's extended attributes.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo
echo "$ARCHIVE"
ls -lh "$ARCHIVE" | awk '{print "  " $5}'
shasum -a 256 "$ARCHIVE" | awk '{print "  sha256 " $1}'
