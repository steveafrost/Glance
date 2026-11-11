#!/bin/bash
# Fail if Glance could reach the network: runs OfflineGuardTests and, when
# given a built app, checks its signed entitlements and that no updater keys
# came back into Info.plist.
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
  # No updater keys: the App Store delivers updates, and Sparkle's presence was
  # the one thing that ever wanted a network connection.
  # Anchored: LSUIElement also starts with "SU", so match the key, not a substring.
  SU=$(/usr/libexec/PlistBuddy -c "Print" "$APP/Contents/Info.plist" 2>/dev/null \
        | grep -cE "^ *(SUFeedURL|SUPublicEDKey|SUEnableAutomaticChecks|SUAutomaticallyUpdate|SUAllowsAutomaticUpdates|SUEnableDownloaderService|SUScheduledCheckInterval) " || true)
  [[ ${SU:-0} -eq 0 ]] || { echo "check-offline: $APP has Sparkle keys in Info.plist" >&2; exit 1; }
  echo "check-offline: $APP has no network entitlement"
fi
echo "check-offline: OK"
