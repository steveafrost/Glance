# Glance

A small native macOS menu bar calendar: today's date in the menu bar, a
month grid and agenda under it, Catppuccin themes, meeting join links and
event editing. Swift 6 (strict concurrency) and AppKit, EventKit for data, no
third-party dependencies. Requires macOS 27.

## Features

- **Menu bar date icon** drawn as a template image and placed in menu bar
  coordinates, so the box is centred on macOS 27's 30pt bar (rows 7–22)
  instead of sitting a point high. Outline or filled style.
- **Clock text** next to the icon from any Unicode date pattern
  (`EEE h:mm a`, `HH:mm:ss`…). The item keeps a fixed width so nothing
  jitters; the icon can be hidden.
- **Month grid + agenda** in a popover-style window under the item. Handles
  multiple displays, auto-hiding and full-screen menu bars, and falls back
  to the screen's top-right corner when the item is hidden.
- **Themes**: Catppuccin Latte, Frappé, Macchiato, Mocha, Catppuccin
  auto (Latte/Mocha) and System light/dark.
- **Meetings**: Zoom, Google Meet, Teams, Webex (and a few others) are found
  in an event's location, URL or notes. The agenda gets a join button
  (opening the native app when installed) and the menu bar shows a camera
  while a call is current or about to start. ⌘J joins it.
- **Events**: create, edit and delete (with confirmation and a this/future
  prompt for repeating events). Declined events are hidden.
- **Calendars**: choose which appear, grouped by account.
- **Week numbers**, highlighted weekdays and first day of week.
- **Global hotkey** (Carbon, recorded in Settings) and **Open at login**.

## Navigating the calendar

- Two-finger swipe left or right over the grid: next or previous month
  (follows your fingers whether or not natural scrolling is on).
- ← / → : previous or next month. ↑ / ↓ : previous or next year.
- ⇧-arrows or h / j / k / l : move the selected day.
- Space or t : jump to today.
- Return : new event on the selected day. Double-click a day does the same.
- Esc : close. ⌘, : Settings. ⌘J : join the current meeting. w : week numbers.

## Building

Needs Xcode 27 (the scripts use `DEVELOPER_DIR`, so `xcode-select` can point
anywhere).

```sh
script/test.sh                 # swift test
script/build-app.sh            # build/Glance.app
script/build-app.sh --install  # replace /Applications/Glance.app and launch it
```

`build-app.sh` signs with the first "Apple Development" identity in the
keychain (override with `GLANCE_SIGN_IDENTITY`, or `-` for ad-hoc). A stable
identity keeps the Calendar permission across rebuilds. The app is sandboxed
with the calendars entitlement and the hardened runtime.

### Layout

- `Sources/GlanceCore` — pure, tested logic: day/week math, month grid,
  per-month event cache, meeting-link parser, clock format, icon geometry,
  popover placement, swipe tracking, agenda rows, event drafts, palettes.
- `Sources/Glance` — the AppKit app. The grid is one layer-backed view that
  draws every cell; the agenda is a view-based table with reused cells;
  EventKit lives on an actor and hands back Sendable snapshots.
- `script/measure-menubar.swift` — measures glyph rows in a menu bar
  screenshot (`screencapture -x -R<x>,0,<w>,30 bar.png`).

### Debug flags

`open /Applications/Glance.app --args <flags>`: `--show` opens the calendar
at launch, `--keep-open` stops it hiding on focus loss, `--print-geometry`
logs the status button geometry (`log show --predicate 'subsystem ==
"com.steveafrost.Glance"'`), `--reference-symbol` adds an SF Symbol item for
alignment checks, `--qa-keys "right,shift+down,return,swipe-left"`
feeds input through the real handlers. Any preference can be overridden for
one run, e.g. `-theme mocha -clockFormat "EEE h:mm a"`.

## Credits

Glance is a from-scratch rewrite whose behaviour is modelled on
[Itsycal](https://www.mowglii.com/itsycal/) by Sanjay Madan (MIT), via
Steve's Catppuccin fork. No Itsycal code is included; see [LICENSE](LICENSE).
Colours are from the [Catppuccin](https://catppuccin.com) palette (MIT).
