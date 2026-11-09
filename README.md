# Glance

A small native macOS menu bar calendar: today's date in the menu bar, a
month grid and agenda under it, Catppuccin themes, meeting join links and
event editing. Swift 6 + AppKit, EventKit for data, no dependencies.

Work in progress; see below for building.

## Navigating the calendar

- Two-finger swipe left or right over the grid: next or previous month
  (follows your fingers whether or not natural scrolling is on).
- ← / → : previous or next month. ↑ / ↓ : previous or next year.
- ⇧-arrows or h / j / k / l : move the selected day.
- Space or t : jump to today.
- Return : new event on the selected day. Esc : close. ⌘, : Settings.

## Credits

Glance is a from-scratch rewrite whose behaviour is modelled on
[Itsycal](https://www.mowglii.com/itsycal/) by Sanjay Madan (MIT), via
Steve's Catppuccin fork. No Itsycal code is included; see [LICENSE](LICENSE).
Colours are from the [Catppuccin](https://catppuccin.com) palette (MIT).
