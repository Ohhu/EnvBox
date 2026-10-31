#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="$ROOT/dist/EnvBox.app"
if [[ -z "${SIGN_IDENTITY:-}" || "${SIGN_IDENTITY}" == "-" ]]; then
    echo "==> Developer ID signing not configured; skipping notarization."
    exit 0
fi
if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "==> Notarization secrets not configured; skipping."
    exit 0
fi
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found" >&2
    exit 1
fi

TMP_ZIP="$ROOT/dist/EnvBox-notarize.zip"
rm -f "$TMP_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$TMP_ZIP"
xcrun notarytool submit "$TMP_ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
rm -f "$TMP_ZIP"
echo "==> App notarized and stapled"
