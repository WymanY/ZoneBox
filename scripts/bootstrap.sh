#!/bin/sh
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate
echo "Generated ZoneBox.xcodeproj. Open it in Xcode or run: make test"
