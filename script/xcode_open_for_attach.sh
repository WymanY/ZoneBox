#!/bin/bash
set -euo pipefail

# Xcode Run pre-action for the ZoneBox AX scheme.
# LaunchStyle is Wait, so this must return immediately and open the app
# after Xcode has started listening. Opening too early misses the attach.
APP="${TARGET_BUILD_DIR:?}/${FULL_PRODUCT_NAME:?}"
(
  sleep 1.5
  if [[ ! -d "$APP" ]]; then
    exit 0
  fi
  pkill -x ZoneBox >/dev/null 2>&1 || true
  sleep 0.2
  /usr/bin/open -n "$APP"
) &
