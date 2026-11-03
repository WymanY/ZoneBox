#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_APP="${ZONEBOX_UPDATE_FIXTURE_APP:-/tmp/zonebox-update-audit-20261027/mount/ZoneBox.app}"
OLD_FIXTURE_APP="${ZONEBOX_UPDATE_OLD_FIXTURE_APP:-/tmp/zonebox-update-audit-20261027/old-mount/ZoneBox.app}"

if [[ ! -d "$FIXTURE_APP" || ! -d "$OLD_FIXTURE_APP" ]]; then
  cat >&2 <<EOF
Update install audit requires two signed Developer ID fixtures:
  ZONEBOX_UPDATE_FIXTURE_APP=$FIXTURE_APP
  ZONEBOX_UPDATE_OLD_FIXTURE_APP=$OLD_FIXTURE_APP

Provide the 0.5.1 and 0.3.0 fixtures, then rerun this command. The regular
unit suite keeps deterministic policy tests separate from this machine-bound audit.
EOF
  exit 2
fi

export ZONEBOX_UPDATE_FIXTURE_APP="$FIXTURE_APP"
export ZONEBOX_UPDATE_OLD_FIXTURE_APP="$OLD_FIXTURE_APP"
xcodebuild \
  -scheme ZoneBox \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.build/VerificationDerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:ZoneBoxTests/UpdateInstallTests
