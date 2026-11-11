#!/bin/bash
# Build Glance for the Mac App Store.
#
#   script/mas-build.sh            # generate project, archive, export Glance.pkg
#   script/mas-build.sh --upload   # ...and upload it to App Store Connect
#
# This is separate from script/build-app.sh on purpose. The store build needs a
# real .app bundle signed with an Apple Distribution identity and the Mac App
# Store provisioning profile, which SwiftPM cannot produce. project.yml
# (xcodegen) describes that build.
#
# Prerequisites, all one-time in the developer portal:
#   - App ID com.steveafrost.Glance
#   - Mac App Store provisioning profile named "Glance Mac App Store"
#   - Apple Distribution and 3rd Party Mac Developer Installer certificates
#
# The upload step needs an App Store Connect app record, which the API refuses
# to create: make one in the web UI first, with SKU 1 and the same bundle ID.
set -euo pipefail
cd "$(dirname "$0")/.."
source script/xcode-env.sh

PROFILE="Glance Mac App Store"
TEAM=4QJ25Y85MX
ARCHIVE="${GLANCE_ARCHIVE:-build/mas/Glance.xcarchive}"
EXPORT="${GLANCE_EXPORT:-build/mas/export}"
PKG="${GLANCE_PKG:-build/mas/Glance.pkg}"

UPLOAD=0
for a in "$@"; do
  case $a in
    --upload) UPLOAD=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "mas-build: xcodegen is required (brew install xcodegen)" >&2; exit 1; }

echo "mas-build: generating Glance.xcodeproj"
xcodegen generate >/dev/null

rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p "$(dirname "$ARCHIVE")" "$EXPORT"

echo "mas-build: archiving"
xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" archive

APP="$ARCHIVE/Products/Applications/Glance.app"
[[ -d $APP ]] || { echo "mas-build: no app in $ARCHIVE" >&2; exit 1; }

# The two things the App Store rejects outright, checked before anything is
# packaged: a network entitlement, or get-task-allow on a release build.
ENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
if grep -q "com.apple.security.network" <<<"$ENTS"; then
  echo "mas-build: $APP has a network entitlement" >&2; exit 1
fi
if grep -q "get-task-allow" <<<"$ENTS"; then
  echo "mas-build: $APP carries get-task-allow" >&2; exit 1
fi
grep -q "com.apple.security.app-sandbox" <<<"$ENTS" || { echo "mas-build: $APP is not sandboxed" >&2; exit 1; }
[[ -f $APP/Contents/embedded.provisionprofile ]] || { echo "mas-build: no embedded profile" >&2; exit 1; }

# pkgbuild signs the component package directly. Exporting through xcodebuild
# needs an existing App Store Connect record and stalls without one.
echo "mas-build: packaging"
pkgbuild --component "$APP" \
  --install-location /Applications \
  --identifier com.steveafrost.Glance \
  --version "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
               "$APP/Contents/Info.plist")" \
  --sign "3rd Party Mac Developer Installer: Steve Frost ($TEAM)" \
  "$PKG"

echo "mas-build: $PKG"
ls -la "$PKG"

if [[ $UPLOAD == 1 ]]; then
  KEY=~/.appstoreconnect/private_keys/AuthKey_NW2J374B7K.p8
  [[ -f $KEY ]] || { echo "mas-build: missing upload key $KEY" >&2; exit 1; }
  echo "mas-build: validating"
  xcrun altool --validate-app -f "$PKG" -t macos --apiKey NW2J374B7K \
    --apiIssuer 4e8ddd0a-9e6c-4877-ae9d-3f7168c02256
  echo "mas-build: uploading"
  xcrun altool --upload-app -f "$PKG" -t macos --apiKey NW2J374B7K \
    --apiIssuer 4e8ddd0a-9e6c-4877-ae9d-3f7168c02256
fi
