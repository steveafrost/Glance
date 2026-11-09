#!/bin/bash
# usage: caretm.sh label [extra args]
L=$1; shift
cd "$(dirname "$0")/.."
pkill -x Glance; sleep 0.5; open /Applications/Glance.app --args --show --keep-open --qa-hotkey "$@"; sleep 3.5
S="$BB_THREAD_STORAGE"
screencapture -x -R3000,0,440,60 $S/$L-shown.png
osascript -e 'tell application "System Events" to keystroke "g" using {command down, option down, control down}'; sleep 1
screencapture -x -R3000,0,440,60 $S/$L-hidden.png
screencapture -x -R3000,0,440,30 $S/$L-bar.png
echo "caret:"; swift script/measure-caret.swift $S/$L-shown.png $S/$L-hidden.png
echo "bar:"; swift script/measure-menubar.swift $S/$L-bar.png | grep "rows 7-22"
