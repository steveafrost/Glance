#!/bin/bash
# Render the calendar popover to a PNG for docs, without Screen Recording
# permission and without any real calendar data.
#
#   script/popover-shot.sh OUT.png [THEME] [YYYY-MM-DD]
#
# How it works: the app has a QA path (`--qa-keys dump-popover`) that draws the
# whole popover into a bitmap via `cacheDisplay` and publishes it on a named
# pasteboard. `--qa-demo-data` swaps EventKit for an invented calendar, so the
# image never contains a real event. Because nothing reads the screen, this
# works on a headless-ish machine, over SSH, and on one with no calendar
# account at all.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${1:?usage: script/popover-shot.sh OUT.png [THEME] [YYYY-MM-DD]}
THEME=${2:-mocha}
DAY=${3:-2026-03-09}
APP=build/Glance.app

[[ -d $APP ]] || { echo "no $APP; run: GLANCE_VERSION=1.0.0 script/build-app.sh --release" >&2; exit 1; }

pkill -x Glance 2>/dev/null || true
sleep 1

# Unset GLANCE_QA_OUT so the app publishes on the pasteboard instead of writing
# into its sandbox container, which the shell cannot read.
env -u GLANCE_QA_OUT open -g "$APP" --args \
    --show --keep-open -theme "$THEME" --qa-day "$DAY" --qa-demo-data \
    --qa-keys dump-popover

# The dump fires 1.5s after launch plus a 1s delay; give the app room to settle.
sleep 8

mkdir -p "$(dirname "$OUT")"
cat > /tmp/popover-extract.swift <<'SWIFT'
import AppKit
let out = CommandLine.arguments[1]
let pb = NSPasteboard(name: .init("com.steveafrost.Glance.qa"))
guard let d = pb.data(forType: .init("com.steveafrost.glance.popover.png")) else {
    FileHandle.standardError.write("no popover png on the QA pasteboard\n".data(using: .utf8)!)
    exit(1)
}
try! d.write(to: URL(fileURLWithPath: out))
SWIFT
swift /tmp/popover-extract.swift "$OUT"
pkill -x Glance 2>/dev/null || true
echo "wrote $OUT"
