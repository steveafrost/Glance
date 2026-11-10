#!/bin/bash
# Render every Glance surface to PNGs for the docs, in both the dark (Mocha)
# and light (Latte) themes, without Screen Recording permission and without any
# real calendar data.
#
#   script/docs-shots.sh [OUTDIR] [DAY]
#
# How it works: the app has QA paths (`--qa-keys dump-*`) that draw each window
# into a bitmap via `cacheDisplay` and publish it on a named pasteboard.
# `--qa-demo-data` swaps EventKit for an invented calendar, so the images never
# contain a real event. Because nothing reads the screen, this works over SSH
# and on a Mac with no calendar account at all.
#
# Surfaces: popover (month grid + agenda), the three Settings tabs, and the
# event editor. Output names are `<surface>-<theme>.png`.
set -euo pipefail
cd "$(dirname "$0")/.."

OUTDIR=${1:-docs}
DAY=${2:-2026-03-09}
APP=build/Glance.app
THEMES=(mocha latte)

[[ -d $APP ]] || { echo "no $APP; run: GLANCE_VERSION=1.0.0 script/build-app.sh --release" >&2; exit 1; }

mkdir -p "$OUTDIR" /tmp/glance-docs

# The app publishes on a pasteboard because the sandbox blocks writing outside
# its container; this helper runs unsandboxed and writes the PNG.
cat > /tmp/glance-docs/extract.swift <<'SWIFT'
import AppKit
let args = CommandLine.arguments
let which = args.count > 2 ? args[2] : "popover"
let type = NSPasteboard.PasteboardType(which == "window"
    ? "com.steveafrost.glance.window.png"
    : "com.steveafrost.glance.popover.png")
let pb = NSPasteboard(name: .init("com.steveafrost.Glance.qa"))
guard let d = pb.data(forType: type) else {
    FileHandle.standardError.write("no \(which) png on the QA pasteboard\n".data(using: .utf8)!)
    exit(1)
}
try! d.write(to: URL(fileURLWithPath: args[1]))
SWIFT

# launch THEME KEYS  — start the app with the QA flags and the given key script.
launch() {
    pkill -x Glance 2>/dev/null || true
    sleep 1
    # Unset GLANCE_QA_OUT so the app publishes on the pasteboard instead of
    # writing into its sandbox container, which the shell cannot read.
    env -u GLANCE_QA_OUT open -g "$APP" --args \
        --show --keep-open -theme "$1" --qa-day "$DAY" --qa-demo-data --qa-keys "$2"
}

# shot SURFACE NAME  — pull the dump off the pasteboard into OUTDIR.
shot() {
    sleep 10
    swift /tmp/glance-docs/extract.swift "$OUTDIR/$2" "$1"
    echo "  wrote $OUTDIR/$2"
}

for theme in "${THEMES[@]}"; do
    echo "$theme:"

    launch "$theme" dump-popover
    shot popover "popover-$theme.png"

    launch "$theme" "cmd+comma,tab-general,dump-settings"
    shot window "settings-general-$theme.png"

    launch "$theme" "cmd+comma,tab-appearance,dump-settings"
    shot window "settings-appearance-$theme.png"

    launch "$theme" "cmd+comma,tab-calendars,dump-settings"
    shot window "settings-calendars-$theme.png"

    launch "$theme" "edit-first,dump-editor"
    shot window "editor-$theme.png"
done

pkill -x Glance 2>/dev/null || true
echo "done"
