#!/bin/bash
# Fail if Glance could reach the network: runs OfflineGuardTests and, when
# given a built app, checks its signed entitlements and that Sparkle's
# Downloader service is enabled.
#
#   script/check-offline.sh [path/to/Glance.app]
set -euo pipefail
cd "$(dirname "$0")/.."
source script/xcode-env.sh
swift test --filter OfflineGuardTests 2>&1 | grep -E "error|failed|Executed" | tail -5
swift test --filter OfflineGuardTests >/dev/null 2>&1 || { echo "check-offline: source checks failed" >&2; exit 1; }

if [[ -n ${1:-} ]]; then
  APP=$1
  ENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
  if grep -q "com.apple.security.network" <<<"$ENTS"; then
    echo "check-offline: $APP is signed with a network entitlement" >&2; exit 1
  fi
  grep -q "com.apple.security.app-sandbox" <<<"$ENTS" || { echo "check-offline: $APP isn't sandboxed" >&2; exit 1; }
  [[ $(/usr/libexec/PlistBuddy -c "Print :SUEnableDownloaderService" "$APP/Contents/Info.plist") == true ]] \
    || { echo "check-offline: SUEnableDownloaderService is off in $APP" >&2; exit 1; }
  echo "check-offline: $APP has no network entitlement"
fi
echo "check-offline: OK"
