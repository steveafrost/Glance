#!/bin/bash
# Measure dot-vs-digit centring for one month, on screen (1x) and in
# offscreen 1x/2x renders. Uses the installed /Applications/Glance.app.
#   script/measure-grid.sh OUTDIR LABEL THEME "qa,keys,before,dump" [app args...]
# Example (December, weekends unshaded):
#   script/measure-grid.sh /tmp/m dec-latte latte right -highlightedWeekdays 0
set -euo pipefail
OUT=$1; LABEL=$2; THEME=$3; KEYS=$4; shift 4
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT/$LABEL"
pkill -x Glance || true; sleep 0.5
open -g /Applications/Glance.app --args --show --keep-open --qa-passive -theme "$THEME" --qa-keys "${KEYS:+$KEYS,}dump-grid" "$@"
sleep "${WAIT:-5}"
# The calendar popover is the Glance window at layer 24.
id=$(swift "$HERE/measure-grid-window.swift")
screencapture -x -o -l"$id" "$OUT/$LABEL/window.png"
swift "$HERE/measure-grid.swift" extract "$OUT/$LABEL"
for spec in "window.png window 1 screen" "render1x.png grid 1 offscreen" "render2x.png grid 2 offscreen"; do
    set -- $spec
    swift "$HERE/measure-grid.swift" measure "$OUT/$LABEL/grid.json" "$OUT/$LABEL/$1" "$2" "$3" "$LABEL $4"
done
