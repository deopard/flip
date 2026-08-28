#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/flip-icon.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
swift "$ROOT/scripts/make-icon.swift" "$WORK" >/dev/null
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "wrote $ROOT/Resources/AppIcon.icns"
