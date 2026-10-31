#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
DMG="$ROOT/dist/EnvBox-$VERSION-macOS-arm64.dmg"

if [[ -z "${SIGN_IDENTITY:-}" || "${SIGN_IDENTITY}" == "-" ]]; then
    echo "==> Developer ID signing not configured; skipping notarization."
    exit 0
fi
if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "==> Notarization secrets not configured; skipping."
    exit 0
fi
if [[ ! -f "$DMG" ]]; then
    echo "error: $DMG not found" >&2
    exit 1
fi

xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "==> DMG notarized and stapled"
