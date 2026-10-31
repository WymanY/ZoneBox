#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zonebox-native-controls.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -swift-version 5 -framework AppKit \
  "$REPO_ROOT/ZoneBox/UI/HoverHelpButton.swift" \
  "$REPO_ROOT/script/native_controls_regression.swift" \
  -o "$TEST_DIR/native-controls"
"$TEST_DIR/native-controls"
