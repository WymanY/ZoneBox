#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTS="$ROOT/.build/DerivedData/Build/Products/Debug"
OUT="${TMPDIR:-/tmp}/zonebox-update-check-restore-regression"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" ]]; then
  TARGET="x86_64-apple-macos14.0"
else
  TARGET="arm64-apple-macos14.0"
fi

if [[ ! -f "$PRODUCTS/libZoneBoxCore.a" ]]; then
  echo "missing $PRODUCTS/libZoneBoxCore.a; build ZoneBoxCore first" >&2
  exit 1
fi

swiftc \
  -sdk "$SDK" \
  -swift-version 5 \
  -target "$TARGET" \
  -I "$PRODUCTS" \
  -L "$PRODUCTS" \
  -lZoneBoxCore \
  -framework AppKit \
  -framework Foundation \
  -framework CryptoKit \
  -o "$OUT" \
  "$ROOT/ZoneBox/Services/GitHubReleaseClient.swift" \
  "$ROOT/ZoneBox/Services/UpdateCenter.swift" \
  "$ROOT/script/update_check_restore_regression.swift"

"$OUT"
