#!/bin/bash
# Pick the Xcode toolchain for the scripts, and export DEVELOPER_DIR.
# Source this from a script that has already cd'd to the repo root.
#
# Order: $DEVELOPER_DIR if set, else the newest /Applications/Xcode*.app,
# else whatever xcode-select points at. Glance's package needs the macOS 26
# SDK, so an older Xcode still fails to build — but with its own version error
# instead of a missing-path error. Named Xcode-<version>.app installs are the
# reason this can't just be /Applications/Xcode.app.

glance_developer_dir() {
  if [[ -n ${DEVELOPER_DIR:-} ]]; then
    printf '%s\n' "$DEVELOPER_DIR"
    return 0
  fi

  local app ver
  local candidates=()
  for app in /Applications/Xcode*.app; do
    [[ -d $app/Contents/Developer ]] || continue
    ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      "$app/Contents/Info.plist" 2>/dev/null) || ver=0
    candidates+=("$ver"$'\t'"$app/Contents/Developer")
  done
  if (( ${#candidates[@]} )); then
    printf '%s\n' "${candidates[@]}" | sort -V -k1,1 | tail -1 | cut -f2-
    return 0
  fi

  xcode-select -p 2>/dev/null && return 0
  return 1
}

if ! DEVELOPER_DIR=$(glance_developer_dir); then
  echo "xcode-env: no Xcode toolchain found; install Xcode or set DEVELOPER_DIR" >&2
  exit 1
fi
export DEVELOPER_DIR
