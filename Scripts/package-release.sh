#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
APP_PATH="$ROOT/dist/EnvBox.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
STAGING="$ROOT/dist/dmg-staging"
DMG="$ROOT/dist/EnvBox-$VERSION-macOS-arm64.dmg"
ZIP="$ROOT/dist/EnvBox-$VERSION-macOS-arm64.zip"
CHECKSUM="$ROOT/dist/SHA256SUMS.txt"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi

echo "==> Creating ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"

echo "==> Creating DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/EnvBox.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
    -volname "EnvBox $VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    echo "==> Signing DMG"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

rm -rf "$STAGING"

echo "==> Checksums"
shasum -a 256 "$DMG" "$ZIP" > "$CHECKSUM"
cat "$CHECKSUM"

echo "==> Release artifacts"
ls -lh "$DMG" "$ZIP" "$CHECKSUM"
