#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -n "${SWIFTC_BIN:-}" ]]; then
    COMPILER="$SWIFTC_BIN"
elif [[ -n "${SWIFT_BIN:-}" ]]; then
    COMPILER="$(dirname "$SWIFT_BIN")/swiftc"
else
    COMPILER="$(command -v swiftc)"
fi
SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
ARCH="$(uname -m)"

mkdir -p .build
"$COMPILER" -sdk "$SDKROOT" -target "${ARCH}-apple-macosx14.0" -O Scripts/make-icon.swift -o .build/make-icon
.build/make-icon Resources
