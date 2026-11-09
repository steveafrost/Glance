#!/bin/bash
# Build Glance.app: release binary, Sparkle.framework, Info.plist, icon,
# entitlements, signature (inside-out).
#
#   script/build-app.sh             # dev build to build/Glance.app (Apple Development)
#   script/build-app.sh --install   # ...and replace /Applications/Glance.app, then launch it
#   script/build-app.sh --release   # Developer ID, secure timestamp, real update feed
#
# Dev signing uses $GLANCE_SIGN_IDENTITY, else the first "Apple Development"
# identity, else ad-hoc. A stable identity keeps the Calendar permission across
# rebuilds. Dev builds get a placeholder feed (never check for updates) unless
# $GLANCE_FEED_URL is set. --release signs with $GLANCE_RELEASE_IDENTITY
# (default "Developer ID Application: Steve Frost (4QJ25Y85MX)").
set -euo pipefail
cd "$(dirname "$0")/.."
source script/xcode-env.sh

MODE=dev; INSTALL=0
for a in "$@"; do
  case $a in
    --install) INSTALL=1 ;;
    --release) MODE=release ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

DEFAULT_FEED=https://github.com/steveafrost/Glance/releases/latest/download/appcast.xml
VERSION="${GLANCE_VERSION:-0.1.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP=build/Glance.app

if [[ $MODE == release ]]; then
  IDENTITY="${GLANCE_RELEASE_IDENTITY:-Developer ID Application: Steve Frost (4QJ25Y85MX)}"
  TIMESTAMP=--timestamp
  FEED="${GLANCE_FEED_URL:-$DEFAULT_FEED}"
else
  IDENTITY="${GLANCE_SIGN_IDENTITY:-}"
  if [[ -z $IDENTITY ]]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | tail -1)
    IDENTITY=${IDENTITY:--}
  fi
  TIMESTAMP=--timestamp=none
  FEED="${GLANCE_FEED_URL:-https://updates.glance.invalid/appcast.xml}"
fi

swift build -c release --arch arm64 --product Glance
BIN_DIR="$(swift build -c release --arch arm64 --product Glance --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Glance" "$APP/Contents/MacOS/Glance"
# ditto keeps the framework's symlinks and its XPC services in place.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# SwiftPM links with @loader_path; the framework lives in Contents/Frameworks.
install_name_tool -delete_rpath @loader_path "$APP/Contents/MacOS/Glance" 2>/dev/null || true
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Glance"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" -e "s|__FEED_URL__|$FEED|" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Inside-out, per Sparkle's sandboxing guide. No --deep: the Downloader
# keeps its own entitlements.
sign() { codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$@"; }
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SP/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SP/XPCServices/Downloader.xpc"
sign "$SP/Autoupdate"
sign "$SP/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Resources/Glance.entitlements "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP (v$VERSION build $BUILD, $MODE), signed with: $IDENTITY"

if [[ $INSTALL == 1 ]]; then
  pkill -x Glance 2>/dev/null && sleep 0.5 || true
  rm -rf /Applications/Glance.app
  cp -R "$APP" /Applications/Glance.app
  open /Applications/Glance.app
  echo "Installed and launched /Applications/Glance.app"
fi
