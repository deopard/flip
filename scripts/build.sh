#!/bin/bash
# Builds Flip.app from the Swift sources. No Xcode project, no dependencies.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Flip.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  "$ROOT/scripts/make-icon.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "Compiling..."
swiftc \
  -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework ApplicationServices \
  -framework Security \
  -o "$APP/Contents/MacOS/Flip" \
  "$ROOT"/Sources/Flip/*.swift

# A fixed certificate keeps the signature identical across rebuilds, so macOS does not
# re-ask for Accessibility permission and the Keychain password every time.
# Create it once with ./scripts/create-signing-identity.sh
IDENTITY_FILE="$ROOT/scripts/.signing-identity"
if [ -f "$IDENTITY_FILE" ]; then
  IDENTITY="$(cat "$IDENTITY_FILE")"
  echo "Signing with the stable development identity..."
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "Signing (ad hoc). Run ./scripts/create-signing-identity.sh to stop the repeated"
  echo "Accessibility and Keychain prompts."
  codesign --force --deep --sign - "$APP"
fi

echo "Built: $APP"
