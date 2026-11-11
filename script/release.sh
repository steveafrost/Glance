#!/bin/bash
# Tag a Glance release and publish source-era release notes.
#
#   script/release.sh tag VERSION       # tag HEAD, push the tag
#   script/release.sh notes VERSION     # print the notes file for VERSION
#
# Glance ships through the Mac App Store, so there is no binary here to build,
# sign, notarize or attach: `script/mas-build.sh --upload` delivers the build,
# and the store carries the downloads and the updates. GitHub keeps the source.
# The tag exists so a version maps to a commit and the notes have somewhere to
# live.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "release: $*" >&2; exit 1; }

cmd=${1:-}; VERSION=${2:-}
[[ -n $cmd && -n $VERSION ]] || die "usage: script/release.sh {tag|notes} VERSION"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.0.4"

case $cmd in
  tag)
    git diff --quiet && git diff --cached --quiet || die "working tree is dirty"
    git fetch --tags --quiet
    if git rev-parse "v$VERSION" >/dev/null 2>&1; then die "tag v$VERSION already exists"; fi
    git tag -a "v$VERSION" -m "Glance $VERSION"
    git push origin "v$VERSION"
    echo "release: tagged and pushed v$VERSION at $(git rev-parse --short HEAD)"
    echo "release: next, script/mas-build.sh --upload, then paste the notes from dist/$VERSION/"
    ;;
  notes)
    [[ -f dist/$VERSION/notes.md ]] || die "no dist/$VERSION/notes.md"
    cat "dist/$VERSION/notes.md"
    ;;
  *)
    die "unknown command $cmd (expected tag or notes)"
    ;;
esac
