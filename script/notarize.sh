#!/bin/bash
# Stage 2 of a Glance release: notarize, staple and re-zip. Self-contained:
# script/release.sh build copies this into the dist folder, so the Mac that
# runs it needs only that folder, Xcode or the Command Line Tools, and a
# notarytool keychain profile. No signing certificate, no Sparkle key.
#
#   ./notarize.sh [DIST_DIR]     # default: the folder this script is in
#
# Profile name: $GLANCE_NOTARY_PROFILE (default "glance").
set -euo pipefail
DIST="${1:-$(cd "$(dirname "$0")" && pwd)}"
PROFILE="${GLANCE_NOTARY_PROFILE:-glance}"
cd "$DIST"
source ./manifest.env   # VERSION, BUILD, ZIP, TEAM_ID
APP=Glance.app
die() { echo "notarize: $*" >&2; exit 1; }

[[ -d $APP && -f $ZIP ]] || die "$DIST has no $APP / $ZIP (run 'script/release.sh build' first)"
xcrun --find notarytool >/dev/null 2>&1 || die "notarytool not found; install Xcode or run: xcode-select --install"
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<MSG
notarize: no notarytool keychain profile named "$PROFILE" on this Mac.

Create it once (it asks for an app-specific password from account.apple.com):

    xcrun notarytool store-credentials "$PROFILE" --apple-id "<your Apple ID email>" --team-id "$TEAM_ID"

Then run this script again. To use another profile name: GLANCE_NOTARY_PROFILE=<name> $0
MSG
  exit 1
fi
codesign --verify --strict --deep "$APP" || die "$APP's signature is broken; rebuild it"

echo "notarize: submitting $ZIP (profile $PROFILE); this usually takes a few minutes"
OUT=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format plist)
ID=$(/usr/libexec/PlistBuddy -c "Print :id" /dev/stdin <<<"$OUT")
STATUS=$(/usr/libexec/PlistBuddy -c "Print :status" /dev/stdin <<<"$OUT")
if [[ $STATUS != Accepted ]]; then
  xcrun notarytool log "$ID" --keychain-profile "$PROFILE" notary-log.json || true
  die "submission $ID: $STATUS. Apple's log is in $DIST/notary-log.json"
fi
xcrun notarytool log "$ID" --keychain-profile "$PROFILE" notary-log.json >/dev/null || true

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
ASSESS=$(spctl --assess --type execute -vv "$APP" 2>&1) || true
echo "$ASSESS"
[[ $ASSESS == *"source=Notarized Developer ID"* ]] || die "Gatekeeper doesn't see $APP as notarized"

# The stapled app is what ships: zip it again.
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
printf 'NOTARY_ID=%s\nNOTARIZED_AT=%s\n' "$ID" "$(date -u +%FT%TZ)" > notarized.env
echo "notarize: done ($ID). Stapled $APP and re-zipped $ZIP."
echo "notarize: move this folder back to the Mac with the Sparkle key and run: script/release.sh publish $VERSION"
