#!/bin/bash
# Build Glance.app for local use: release binary, Info.plist, icon,
# entitlements, signature.
#
#   script/build-app.sh             # dev build to build/Glance.app (Apple Development)
#   script/build-app.sh --install   # ...and replace /Applications/Glance.app, then launch it
#
# Dev signing uses $GLANCE_SIGN_IDENTITY, else the first "Apple Development"
# identity, else ad-hoc. A stable identity keeps the Calendar permission across
# rebuilds.
#
# This is the local/QA build. It is NOT the App Store build: that one is
# `xcodegen generate && xcodebuild archive` from project.yml, signed with an
# Apple Distribution identity and the Mac App Store provisioning profile.
# See script/mas-build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
source script/xcode-env.sh

INSTALL=0
for a in "$@"; do
  case $a in
    --install) INSTALL=1 ;;
    --release) echo "build-app: --release is gone; the App Store build is script/mas-build.sh" >&2; exit 2 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

VERSION="${GLANCE_VERSION:-0.1.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP=build/Glance.app

IDENTITY="${GLANCE_SIGN_IDENTITY:-}"
if [[ -z $IDENTITY ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | tail -1)
  IDENTITY=${IDENTITY:--}
fi

swift build -c release --arch arm64 --product Glance
BIN_DIR="$(swift build -c release --arch arm64 --product Glance --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Glance" "$APP/Contents/MacOS/Glance"
# SwiftPM links with @loader_path; keep the rpath pointing inside the bundle so
# the embedded GlanceCore framework resolves once one is copied in.
install_name_tool -delete_rpath @loader_path "$APP/Contents/MacOS/Glance" 2>/dev/null || true
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Glance"
if [[ -d $BIN_DIR/GlanceCore.framework ]]; then
  ditto "$BIN_DIR/GlanceCore.framework" "$APP/Contents/Frameworks/GlanceCore.framework"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Info.plist carries $(MARKETING_VERSION)/$(CURRENT_PROJECT_VERSION) for the
# Xcode App Store build; fill them in here for the SwiftPM dev build.
sed -e "s/\$(MARKETING_VERSION)/$VERSION/g" -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/g" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

sign() { codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$@"; }
[[ -d $APP/Contents/Frameworks/GlanceCore.framework ]] && sign "$APP/Contents/Frameworks/GlanceCore.framework"
sign --entitlements Resources/Glance.entitlements "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP (v$VERSION build $BUILD), signed with: $IDENTITY"

if [[ $INSTALL == 1 ]]; then
  [[ -w /Applications ]] || { echo "build-app: no write access to /Applications" >&2; exit 1; }
  # Quit a running copy and clear the QA pasteboard so --qa-* flags start clean.
  osascript -e 'quit app "Glance"' 2>/dev/null || true
  rm -rf /Applications/Glance.app
  ditto "$APP" /Applications/Glance.app
  open /Applications/Glance.app
  echo "Installed /Applications/Glance.app"
fi
