#!/bin/bash
# Release Glance in three stages that can run on different Macs. See README › Releasing.
#
#   script/release.sh build VERSION     # this repo + Developer ID cert: build, sign, zip → dist/Glance-VERSION/
#   dist/Glance-VERSION/notarize.sh     # any Mac with a notarytool profile: notarize, staple, re-zip
#   script/release.sh publish VERSION   # this repo + Sparkle EdDSA key + gh: appcast, GitHub release
#
# (script/release.sh notarize VERSION runs the dist folder's notarize.sh.)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}"
REPO=steveafrost/Glance
die() { echo "release: $*" >&2; exit 1; }

STAGE=${1:-}; VERSION=${2:-}
[[ $STAGE =~ ^(build|notarize|publish)$ && -n $VERSION ]] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ $VERSION =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "VERSION must look like 1.2 or 1.2.3"
DIST=dist/Glance-$VERSION
ZIP=Glance-$VERSION.zip
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

build() {
  [[ -z $(git status --porcelain) || -n ${GLANCE_ALLOW_DIRTY:-} ]] \
    || die "uncommitted changes; commit first (or GLANCE_ALLOW_DIRTY=1 for a trial build)"
  [[ ! -e $DIST ]] || die "$DIST exists; remove it to rebuild"
  GLANCE_VERSION=$VERSION script/build-app.sh --release
  script/check-offline.sh build/Glance.app
  local team
  team=$(codesign -dv build/Glance.app 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [[ -n $team && $team != "not set" ]] || die "build/Glance.app has no team identifier"
  codesign -dv build/Glance.app 2>&1 | grep -q "Authority=Developer ID Application" || die "not signed with Developer ID"
  codesign -d --verbose=4 build/Glance.app 2>&1 | grep -q "Timestamp=" || die "no secure timestamp"

  mkdir -p "$DIST"
  ditto build/Glance.app "$DIST/Glance.app"
  ditto -c -k --sequesterRsrc --keepParent "$DIST/Glance.app" "$DIST/$ZIP"
  cp script/notarize.sh "$DIST/notarize.sh"
  local build_no
  build_no=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$DIST/Glance.app/Contents/Info.plist")
  printf 'VERSION=%s\nBUILD=%s\nZIP=%s\nTEAM_ID=%s\nCOMMIT=%s\n' \
    "$VERSION" "$build_no" "$ZIP" "$team" "$(git rev-parse HEAD)" > "$DIST/manifest.env"
  if [[ ! -f $DIST/Glance-$VERSION.md ]]; then
    { echo "## Glance $VERSION"; echo
      local prev; prev=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
      git log --no-merges --format='- %s' ${prev:+$prev..}HEAD | grep -v '^- QA' | head -30
    } > "$DIST/Glance-$VERSION.md"
  fi
  echo
  echo "release: built $DIST (v$VERSION build $build_no, team $team)"
  echo "release: edit the release notes in $DIST/Glance-$VERSION.md, then notarize:"
  echo "  here:            $DIST/notarize.sh"
  echo "  on another Mac:  ditto -c -k --keepParent $DIST Glance-$VERSION-dist.zip, copy it over,"
  echo "                   ditto -x -k Glance-$VERSION-dist.zip . && Glance-$VERSION/notarize.sh"
}

publish() {
  [[ -f $DIST/manifest.env ]] || die "$DIST is missing; run 'script/release.sh build $VERSION' first"
  [[ -f $DIST/notarized.env ]] || die "$DIST hasn't been notarized; run $DIST/notarize.sh"
  source "$DIST/manifest.env"
  xcrun stapler validate "$DIST/Glance.app" >/dev/null || die "$DIST/Glance.app has no stapled ticket"
  [[ -x $SPARKLE_BIN/generate_appcast ]] || die "Sparkle tools missing; run: swift package resolve"
  "$SPARKLE_BIN/generate_keys" -p >/dev/null 2>&1 \
    || die "no Sparkle EdDSA key in this Mac's keychain. Import the backup: $SPARKLE_BIN/generate_keys -f <file>"
  [[ $("$SPARKLE_BIN/generate_keys" -p) == $(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$DIST/Glance.app/Contents/Info.plist") ]] \
    || die "the keychain's EdDSA key doesn't match SUPublicEDKey in the app"
  gh auth status >/dev/null 2>&1 || die "gh isn't signed in"
  [[ $(gh repo view $REPO --json visibility -q .visibility) == PUBLIC ]] \
    || die "$REPO is private; the update feed must be public"
  ! gh release view "v$VERSION" --repo $REPO >/dev/null 2>&1 || die "release v$VERSION already exists"

  # generate_appcast updates an existing appcast with the new archive: start
  # from the one in the latest release so older versions stay listed.
  local feed=$DIST/feed
  rm -rf "$feed"; mkdir -p "$feed"
  gh release download --repo $REPO --pattern appcast.xml --dir "$feed" 2>/dev/null || echo "release: first release, new appcast"
  cp "$DIST/$ZIP" "$DIST/Glance-$VERSION.md" "$feed/"
  "$SPARKLE_BIN/generate_appcast" --embed-release-notes \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "https://github.com/$REPO" "$feed"
  grep -q "releases/download/v$VERSION/$ZIP" "$feed/appcast.xml" || die "appcast has no item for $ZIP"
  # Check the new item's EdDSA signature against the archive.
  local sig
  sig=$(grep -A6 "v$VERSION/$ZIP" "$feed/appcast.xml" | grep -o 'sparkle:edSignature="[^"]*"' | head -1 | cut -d'"' -f2)
  "$SPARKLE_BIN/sign_update" --verify "$feed/$ZIP" "$sig" || die "EdDSA signature check failed"

  gh release create "v$VERSION" --repo $REPO --target "$COMMIT" --title "Glance $VERSION" \
    --notes-file "$DIST/Glance-$VERSION.md" "$DIST/$ZIP" "$feed/appcast.xml"
  echo "release: published v$VERSION. Feed: https://github.com/$REPO/releases/latest/download/appcast.xml"
}

case $STAGE in
  build) build ;;
  notarize) [[ -x $DIST/notarize.sh ]] || die "$DIST is missing; build first"; "$DIST/notarize.sh" "$DIST" ;;
  publish) publish ;;
esac
