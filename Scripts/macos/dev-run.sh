#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SWIFT_BIN="${SWIFT_BIN:-$(command -v swift)}"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_PATH="$ROOT/dist/EnvBox.app"

"$SWIFT_BIN" build --disable-sandbox -c "$CONFIGURATION"
BIN_DIR="$("$SWIFT_BIN" build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/EnvBox" "$APP_PATH/Contents/MacOS/EnvBox"
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp -R shared/ui/assets "$APP_PATH/Contents/Resources/web"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.0" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH" >/dev/null
open "$APP_PATH"
