#!/bin/bash
# Builds Flip and puts it in /Applications, which is where Spotlight, Launchpad and
# "Open at Login" look. Running it from a build directory works but Spotlight will not
# index it there.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="/Applications/Flip.app"

"$ROOT/scripts/build.sh"

if pgrep -f "Flip.app/Contents/MacOS/Flip" >/dev/null 2>&1; then
    echo "Quitting the running copy..."
    pkill -f "Flip.app/Contents/MacOS/Flip" || true
    sleep 1
fi

echo "Installing to $DESTINATION..."
rm -rf "$DESTINATION"
cp -R "$ROOT/build/Flip.app" "$DESTINATION"

# Spotlight indexes on its own schedule; nudge it so the app is findable straight away.
mdimport "$DESTINATION" 2>/dev/null || true

open "$DESTINATION"
echo
echo "Installed. Flip is now in /Applications and searchable from Spotlight."
echo "The signature is unchanged, so the Accessibility permission carries over."
