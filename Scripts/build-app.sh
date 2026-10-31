#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SWIFT_BIN="${SWIFT_BIN:-$(command -v swift)}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_PATH="$ROOT/dist/EnvBox.app"
MIN_MACOS="14.0"
TARGET_ARCH="arm64"
TRIPLE="${TARGET_ARCH}-apple-macosx${MIN_MACOS}"
SCRATCH=".build/release-${TARGET_ARCH}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: VERSION must be a stable semantic version (for example 1.0.0), got: $VERSION" >&2
    exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: BUILD_NUMBER must be numeric, got: $BUILD_NUMBER" >&2
    exit 1
fi

echo "==> EnvBox $VERSION ($BUILD_NUMBER)"
echo "==> Swift: $("$SWIFT_BIN" --version | head -1)"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating AppIcon.icns"
    SWIFT_BIN="$SWIFT_BIN" ./Scripts/make-icon.sh
fi

mkdir -p .build/bin dist

echo "==> Building $TARGET_ARCH"
"$SWIFT_BIN" build \
    --disable-sandbox \
    -c "$CONFIGURATION" \
    --triple "$TRIPLE" \
    --scratch-path "$SCRATCH"

BIN_DIR="$("$SWIFT_BIN" build \
    --disable-sandbox \
    -c "$CONFIGURATION" \
    --triple "$TRIPLE" \
    --scratch-path "$SCRATCH" \
    --show-bin-path)"
if [[ ! -x "$BIN_DIR/EnvBox" ]]; then
    echo "error: missing executable at $BIN_DIR/EnvBox" >&2
    exit 1
fi
if [[ ! -x "$BIN_DIR/envbox-helper" ]]; then
    echo "error: missing helper executable at $BIN_DIR/envbox-helper" >&2
    exit 1
fi

FINAL_BINARY=".build/bin/EnvBox-$TARGET_ARCH"
cp "$BIN_DIR/EnvBox" "$FINAL_BINARY"
lipo -info "$FINAL_BINARY"

echo "==> Assembling app bundle"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Helpers"
cp "$FINAL_BINARY" "$APP_PATH/Contents/MacOS/EnvBox"
chmod 755 "$APP_PATH/Contents/MacOS/EnvBox"
cp "$BIN_DIR/envbox-helper" "$APP_PATH/Contents/Helpers/envbox"
chmod 755 "$APP_PATH/Contents/Helpers/envbox"
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
chmod 644 "$APP_PATH/Contents/Info.plist" "$APP_PATH/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Signing ad-hoc (set SIGN_IDENTITY for Developer ID)"
    codesign --force --options runtime --sign - "$APP_PATH/Contents/Helpers/envbox"
    codesign --force --options runtime --entitlements Resources/EnvBox.entitlements --sign - "$APP_PATH"
else
    echo "==> Signing with $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH/Contents/Helpers/envbox"
    codesign --force --options runtime --timestamp --entitlements Resources/EnvBox.entitlements --sign "$SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "==> Built $APP_PATH"
