#!/bin/bash
# Build Glance.app: release binary, Info.plist, icon, entitlements, signature.
#
#   script/build-app.sh            # build to build/Glance.app
#   script/build-app.sh --install  # ...and replace /Applications/Glance.app, then launch it
#
# Signing: uses $GLANCE_SIGN_IDENTITY, else the first "Apple Development"
# identity in the keychain, else ad-hoc ("-"). A stable identity keeps the
# Calendar permission across rebuilds; ad-hoc builds may ask again.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}"

VERSION="${GLANCE_VERSION:-0.1.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP=build/Glance.app

swift build -c release --arch arm64 --product Glance
BIN="$(swift build -c release --arch arm64 --product Glance --show-bin-path)/Glance"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glance"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${GLANCE_SIGN_IDENTITY:-}"
if [[ -z $IDENTITY ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | tail -1)
  IDENTITY=${IDENTITY:--}
fi
codesign --force --options runtime --timestamp=none --entitlements Resources/Glance.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (v$VERSION build $BUILD), signed with: $IDENTITY"

if [[ ${1:-} == --install ]]; then
  pkill -x Glance 2>/dev/null && sleep 0.5 || true
  rm -rf /Applications/Glance.app
  cp -R "$APP" /Applications/Glance.app
  open /Applications/Glance.app
  echo "Installed and launched /Applications/Glance.app"
fi
