import AppKit
import GlanceCore
import os

private let log = Logger(subsystem: "com.steveafrost.Glance", category: "app")

/// Wires the status item, calendar window, data model, timers and settings together.
@MainActor
final class AppController: NSObject, NSWindowDelegate {
    private let prefs = Preferences.shared
    private let model = CalendarModel()
    private let status = StatusItemController()
    private let window = PopoverWindow()
    private let content: CalendarContentView
    private var settings: SettingsWindowController?
    private var editorPanel: PopoverWindow?
    private var editorController: EventEditorController?
    private var editorShown: Bool { editorPanel?.isVisible == true }

    private var month: MonthKey
    private var selected: DayKey
    private var today: DayKey
    private var lastPlacement: PopoverPlacement.Result?
    private var hiddenAt: Date?
    private var meeting = MeetingSchedule.State(activeEventID: nil, nextChange: nil)
    private var clockTimer: Timer?
    private var meetingTimer: Timer?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private var referenceItem: NSStatusItem?
    /// `--keep-open`: don't hide on losing focus (for screenshots while testing).
    private let keepOpenForQA = ProcessInfo.processInfo.arguments.contains("--keep-open")
    /// `--qa-passive`: show without becoming the key window, so typing in
    /// other apps never lands in Glance during QA (QA keys still reach the grid).
    private let passiveForQA = ProcessInfo.processInfo.arguments.contains("--qa-passive")

    override init() {
        let cal = Calendar.autoupdatingCurrent
        let t = DayKey(date: Date(), calendar: cal)
        today = t
        selected = t
        month = t.monthKey
        let grid = MonthGridView(model: .init(grid: MonthGrid(month: t.monthKey, firstWeekday: Preferences.shared.firstWeekday),
                                              selected: t, today: t, highlighted: Preferences.shared.highlightedWeekdays,
                                              dots: [:], geometry: GridGeometry(showsWeekNumbers: Preferences.shared.showWeekNumbers,
                                                                    rows: MonthGrid(month: t.monthKey, firstWeekday: Preferences.shared.firstWeekday).visibleRows)))
        content = CalendarContentView(grid: grid)
        super.init()
    }

    // MARK: Startup

    func start() {
        window.delegate = self
        window.onCancel = { [weak self] in self?.hideCalendar() }
        window.frameView.addSubview(content)

        status.onClick = { [weak self] in self?.toggleCalendar() }
        status.onOpenSettings = { [weak self] in self?.openSettings(nil) }
        model.onChange = { [weak self] in self?.dataChanged() }
        HotKeyCenter.shared.onPress = { [weak self] in self?.toggleCalendar() }
        if let message = HotKeyCenter.shared.register(prefs.hotKey) { log.error("hotkey: \(message, privacy: .public)") }
        if ProcessInfo.processInfo.arguments.contains("--qa-hotkey") {
            // QA: ⌃⌥⌘G for this run only (not saved).
            let combo = KeyCombo(keyCode: 5, carbonModifiers: KeyCombo.cmdKey | KeyCombo.optionKey | KeyCombo.controlKey)
            log.notice("qa hotkey register: \(HotKeyCenter.shared.register(combo) ?? "ok", privacy: .public)")
        }

        wireContent()
        applyTheme()
        observeSystem()
        scheduleClockTick()
        Task { await model.start(); refreshAll() }

        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reference-symbol") { addReferenceSymbolItem() }
        if args.contains("--print-geometry") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                log.notice("geometry \(self.status.geometryDescription(), privacy: .public)")
            }
        }
        if let i = args.firstIndex(of: "--qa-keys"), i + 1 < args.count {
            // QA: after showing, feed key events (e.g. "right,shift+down,return") through the panel.
            let script = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.sendQAKeys(script) }
        }
        if let i = args.firstIndex(of: "--qa-day"), i + 1 < args.count {
            // QA: start on this day (YYYY-MM-DD) instead of today, with no key presses.
            let p = args[i + 1].split(separator: "-").compactMap { Int($0) }
            if p.count == 3 {
                selected = DayKey(year: p[0], month: p[1], day: p[2])
                month = selected.monthKey
            }
        }
        if let flagIndex = args.firstIndex(of: "--qa-only-calendars"), flagIndex + 1 < args.count {
            // QA: show only calendars whose title matches this comma-separated
            // list, so screenshots for the README contain no personal data.
            // Overrides the saved selection for this launch only.
            model.qaOnlyCalendarTitles = Set(
                args[flagIndex + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
        }
        // First run (calendar permission never asked): open the calendar
        // under the icon so a new user sees where Glance lives, next to the
        // permission prompt.
        let firstRun = EventRepository.authorization == .notDetermined && !args.contains { $0.hasPrefix("--qa") }
        if args.contains("--show") || firstRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showCalendar() }
        }
    }

    private func sendQAKeys(_ script: String) {
        let codes: [String: (UInt16, String)] = [
            "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "down": (125, "\u{F701}"), "up": (126, "\u{F700}"),
            "return": (36, "\r"), "escape": (53, "\u{1b}"), "space": (49, " "), "comma": (43, ","),
            "tab": (48, "\t"), "delete": (51, "\u{8}"),
        ]
        var delay = 0.0
        for token in script.split(separator: ",") {
            var parts = token.split(separator: "+").map(String.init)
            let key = parts.removeLast()
            var flags: NSEvent.ModifierFlags = []
            if parts.contains("shift") { flags.insert(.shift) }
            if parts.contains("cmd") { flags.insert(.command) }
            if key.hasPrefix("tab-") {
                // Switch the Settings tab: tab-general, tab-appearance, tab-calendars.
                let name = String(key.dropFirst(4))
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.settings?.selectTab(named: name)
                    log.notice("qa \(String(token), privacy: .public)")
                }
                delay += 0.8
                continue
            }
            if let dump = qaDumpAction(for: key) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { dump.run() }
                delay += dump.delay
                continue
            }
            if key == "edit-first" {
                // Open the editor on the first timed agenda event (no changes are saved).
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    let first = self.content.agenda.rows.lazy.compactMap { row -> EventSnapshot? in
                        if case .event(let e, _) = row, !e.isAllDay { return e }
                        return nil
                    }.first
                    if let first { self.edit(first) }
                    log.notice("qa edit-first \(first != nil)")
                }
                delay += 0.6
                continue
            }
            if key.hasPrefix("swipe") {
                // "swipe-left" / "swipe-right": a phased trackpad gesture plus momentum, fingers moving that way.
                let fingersLeft = key == "swipe-left"
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    log.notice("qa \(String(token), privacy: .public)")
                    for e in Self.qaSwipeEvents(fingersLeft: fingersLeft) { self.content.grid.scrollWheel(with: e) }
                    log.notice("qa state month=\(self.month.description, privacy: .public)")
                }
                delay += 0.4
                continue
            }
            let (code, chars) = codes[key] ?? (0, key)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                // Keys go to the key window (the editor when it is open).
                let target = NSApp.keyWindow ?? self.window
                guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                                          windowNumber: target.windowNumber, context: nil, characters: chars,
                                                          charactersIgnoringModifiers: flags.contains(.shift) ? chars.uppercased() : chars,
                                                          isARepeat: false, keyCode: code) else { return }
                log.notice("qa key \(String(token), privacy: .public)")
                target.sendEvent(e)
                log.notice("qa state month=\(self.month.description, privacy: .public) selected=\(self.selected.description, privacy: .public) visible=\(self.window.isVisible) editor=\(self.editorShown) settings=\(self.settings?.window?.isVisible == true)")
            }
            delay += 0.4
        }
    }

    /// A `--qa-keys` token that renders something offscreen, or nil.
    ///
    /// The dumps go through `cacheDisplay`, so they need no Screen Recording
    /// permission and, with `--qa-demo-data`, no calendar data either.
    private func qaDumpAction(for key: String) -> (delay: Double, run: @MainActor () -> Void)? {
        switch key {
        case "dump-grid":
            return (delay: 0.5, run: { [weak self] in
                guard let self else { return }
                self.content.grid.publishQADump(background: self.colors.background)
                log.notice("qa dump-grid \(self.content.grid.model.grid.month.description, privacy: .public)")
            })
        case "dump-popover":
            let outPath = ProcessInfo.processInfo.environment["GLANCE_QA_OUT"]
            return (delay: 1.0, run: { [weak self] in
                guard let self else { return }
                self.content.publishPopoverDump(background: self.colors.background, path: outPath)
            })
        case "dump-settings":
            return (delay: 1.0, run: { [weak self] in
                guard let self, let window = self.settings?.window else {
                    log.notice("qa dump-settings: no settings window")
                    return
                }
                WindowQADump.publish(window, label: "settings")
            })
        case "dump-editor":
            // Pair with `edit-first`: opening the editor awaits an async draft,
            // so the panel appears an indeterminate moment later. Poll for it
            // rather than guessing a delay.
            return (delay: 0.5, run: { [weak self] in
                self?.dumpEditorWhenReady(attempts: 20)
            })
        default:
            return nil
        }
    }

    /// Render the editor once its async draft has resolved. QA only.
    private func dumpEditorWhenReady(attempts: Int) {
        guard let panel = editorPanel else {
            guard attempts > 0 else {
                log.notice("qa dump-editor: no editor panel")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.dumpEditorWhenReady(attempts: attempts - 1)
            }
            return
        }
        // Give the panel one layout pass so its views have real sizes.
        panel.displayIfNeeded()
        // The editor focuses the title field and selects its text. Keep the focus
        // ring but drop the selection, which looks like a highlight in a still.
        if let field = panel.firstResponder as? NSTextView {
            field.setSelectedRange(NSRange(location: field.string.count, length: 0))
        }
        WindowQADump.publish(panel, label: "editor")
    }

    /// Scroll events for a QA swipe: began, 12 changed, ended, then 20 momentum events.
    private static func qaSwipeEvents(fingersLeft: Bool) -> [NSEvent] {
        // Synthesised events report isDirectionInvertedFromDevice == false
        // (classic scrolling), where the raw delta is opposite to the fingers.
        let dx: Int32 = fingersLeft ? 8 : -8
        func make(_ d: Int32, phase: Int64, momentum: Int64) -> NSEvent? {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: d, wheel3: 0) else { return nil }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            return NSEvent(cgEvent: cg)
        }
        var events = [make(0, phase: 1, momentum: 0)]
        events += (0..<12).map { _ in make(dx, phase: 2, momentum: 0) }
        events.append(make(0, phase: 4, momentum: 0))
        events.append(make(dx * 3, phase: 0, momentum: 1))
        events += (0..<20).map { _ in make(dx * 3, phase: 0, momentum: 2) }
        events.append(make(0, phase: 0, momentum: 3))
        return events.compactMap { $0 }
    }

    /// A second status item with the SF Symbol "calendar", for comparing
    /// vertical alignment with a system-drawn symbol (`--reference-symbol`).
    private func addReferenceSymbolItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Reference")
        referenceItem = item
    }

    private func wireContent() {
        let grid = content.grid
        grid.onSelect = { [weak self] day in self?.select(day) }
        grid.onDoubleClick = { [weak self] day in self?.select(day); self?.newEvent(on: day) }
        grid.onCommand = { [weak self] cmd in self?.perform(cmd) }

        content.addButton.target = self
        content.addButton.action = #selector(addEvent)
        content.menuButton.target = self
        content.menuButton.action = #selector(showOptionsMenu(_:))

        let agenda = content.agenda
        agenda.onEdit = { [weak self] e in self?.edit(e) }
        agenda.onJoin = { [weak self] e in self?.join(e) }
        agenda.onDelete = { [weak self] e in self?.confirmDelete(e) }
        agenda.onOpenInCalendar = { [weak self] e in self?.openInCalendar(e) }
        content.accessView.button.target = self
        content.accessView.button.action = #selector(fixAccess)
    }

    private func onNotification(_ name: Notification.Name, center: NotificationCenter = .default, object: AnyObject? = nil,
                                _ handler: @escaping @MainActor (_ preferenceKey: String?) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { note in
            let key = Preferences.key(of: note)
            MainActor.assumeIsolated { handler(key) }
        }
        observers.append((center, token))
    }

    private func observeSystem() {
        // Day rollover, clock and time zone changes, wake: event-driven, no polling.
        onNotification(.NSCalendarDayChanged) { [weak self] _ in self?.dayMayHaveChanged(resetSelection: true) }
        onNotification(.NSSystemClockDidChange) { [weak self] _ in self?.timeChanged() }
        onNotification(.NSSystemTimeZoneDidChange) { [weak self] _ in self?.timeChanged() }
        onNotification(NSLocale.currentLocaleDidChangeNotification) { [weak self] _ in
            self?.status.configureClock(); self?.refreshAll()
        }
        onNotification(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] _ in
            self?.timeChanged()
        }
        onNotification(NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.status.update()
            if self?.window.isVisible == true { self?.positionWindow(initial: false) }
        }
        onNotification(NSApplication.didBecomeActiveNotification) { [weak self] _ in self?.model.recheckAccess() }
        onNotification(Preferences.didChange) { [weak self] key in self?.preferenceChanged(key) }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(interfaceThemeChanged),
                                                            name: .init("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    @objc private func interfaceThemeChanged() {
        DispatchQueue.main.async { [weak self] in self?.applyTheme() }
    }

    // MARK: Time

    private func timeChanged() {
        dayMayHaveChanged(resetSelection: false)
        status.configureClock()
        scheduleClockTick()
        model.reloadNow()
    }

    private func dayMayHaveChanged(resetSelection: Bool) {
        let t = DayKey(date: Date(), calendar: model.calendar)
        guard t != today else { status.update(); return }
        let wasOnToday = selected == today
        today = t
        if resetSelection || wasOnToday, !window.isVisible {
            selected = t
            month = t.monthKey
        }
        status.update()
        refreshAll()
    }

    /// One-shot timer aligned to the next minute (or second) the clock text can change.
    private func scheduleClockTick() {
        clockTimer?.invalidate()
        clockTimer = nil
        let clock = status.clock
        guard !clock.isEmpty, clock.usesTime else { return }
        let fire = clock.nextTick(after: Date(), calendar: model.calendar)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.status.update()
                self?.scheduleClockTick()
            }
        }
        timer.tolerance = clock.usesSeconds ? 0.05 : 0.3
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    /// Meeting indicator: recompute now, then sleep until the next change.
    private func updateMeetingState() {
        let now = Date()
        let events = model.events(on: today) + model.events(on: today.adding(days: 1))
        let state = MeetingSchedule.state(events: events, now: now, lead: TimeInterval(prefs.meetingLeadMinutes * 60))
        meeting = state
        content.agenda.activeMeetingID = state.activeEventID
        meetingTimer?.invalidate()
        meetingTimer = nil
        guard let next = state.nextChange else { return }
        let timer = Timer(fire: next.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMeetingState() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        meetingTimer = timer
    }

    // MARK: Preferences

    private func preferenceChanged(_ key: String?) {
        switch key {
        case "theme": applyTheme()
        case "clockFormat": status.configureClock(); scheduleClockTick()
        case "hideIcon", "iconStyle": status.update()
        case "meetingLeadMinutes": updateMeetingState()
        case "hotKey":
            if let message = HotKeyCenter.shared.register(prefs.hotKey) { settings?.showHotKeyError(message) }
        case "selectedCalendarIDs": model.selectionChanged()
        default: refreshAll()
        }
    }

    private func applyTheme() {
        let appearance = ThemeColors.forcedAppearance
        window.appearance = appearance
        let effective = appearance ?? NSApp.effectiveAppearance
        var colors: ThemeColors!
        withAppearance(effective) { colors = ThemeColors.current(for: effective) }
        window.frameView.fillColor = colors.background
        window.frameView.borderColor = colors.divider
        content.apply(colors)
        content.grid.needsDisplay = true
        refreshAll()
    }

    private var colors: ThemeColors {
        let a = window.appearance ?? NSApp.effectiveAppearance
        return ThemeColors.current(for: a)
    }

    // MARK: Data → UI

    private var visibleRange: VisibleRange {
        VisibleRange(grid: MonthGrid(month: month, firstWeekday: prefs.firstWeekday), selected: selected, agendaDays: prefs.agendaDays)
    }

    private func refreshAll() {
        model.show(visibleRange)
        dataChanged()
    }

    private func dataChanged() {
        let grid = MonthGrid(month: month, firstWeekday: prefs.firstWeekday)
        let range = VisibleRange(grid: grid, selected: selected, agendaDays: prefs.agendaDays)
        let byDay = model.eventsByDay(in: range)

        var dots: [DayKey: [NSColor]] = [:]
        if prefs.showEventDots {
            for day in grid.days {
                guard let events = byDay[day], !events.isEmpty else { continue }
                var seen = Set<String>(), colors: [NSColor] = []
                for e in events where seen.insert(e.calendarID).inserted {
                    colors.append(NSColor(rgba: e.color))
                }
                dots[day] = colors
            }
        }
        // Only the month's own weeks; the agenda takes the rest (AgendaSizing).
        let geometry = GridGeometry(showsWeekNumbers: prefs.showWeekNumbers, rows: grid.visibleRows)
        let rowsChanged = geometry.rows != content.grid.model.geometry.rows
        content.grid.model = .init(grid: grid, selected: selected, today: today,
                                   highlighted: prefs.highlightedWeekdays, dots: dots, geometry: geometry)

        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        content.monthLabel.stringValue = f.string(from: month.firstDay.startDate(in: model.calendar))

        switch model.access {
        case .granted:
            content.showsAccessMessage = false
        case .unknown:
            content.showsAccessMessage = true
            content.accessView.label.stringValue = "Glance is waiting for permission to read your calendars."
            content.accessView.button.title = "Allow Calendar Access…"
        case .denied:
            content.showsAccessMessage = true
            content.accessView.label.stringValue = "Glance doesn’t have access to your calendars. Turn on Full Access for Glance in System Settings › Privacy & Security › Calendars."
            content.accessView.button.title = "Open Privacy Settings"
        case .error(let message):
            content.showsAccessMessage = true
            content.accessView.label.stringValue = "Glance couldn’t request calendar access: \(message)"
            content.accessView.button.title = "Open Privacy Settings"
        }

        content.agenda.today = today
        content.agenda.calendar = model.calendar
        content.agenda.setRows(Agenda.rows(eventsByDay: byDay, start: selected, days: prefs.agendaDays,
                                           showEmptyDays: prefs.showEmptyAgendaDays))
        updateMeetingState()
        // The grid moves the agenda even when the window size doesn't change.
        if rowsChanged { content.needsLayout = true }
        if window.isVisible { positionWindow(initial: false) }
    }

    // MARK: Window

    func toggleCalendar() {
        log.notice("toggle (visible=\(self.window.isVisible))")
        if window.isVisible && window.occlusionState.contains(.visible) {
            // Clicking the item on another display moves the window there.
            if let frame = status.screenFrame, let idx = PopoverPlacement.screenIndex(for: frame, in: screens),
               NSScreen.screens[idx].frame != lastPlacement?.screenFrame {
                positionWindow(initial: true)
                return
            }
            hideCalendar()
        } else {
            showCalendar()
        }
    }

    func showCalendar() {
        // After 10 minutes away, come back to today.
        if let hiddenAt, Date().timeIntervalSince(hiddenAt) > 600 {
            selected = today
            month = today.monthKey
        }
        refreshAll()
        positionWindow(initial: true)
        NSApp.unhideWithoutActivation()
        if passiveForQA { window.orderFrontRegardless() } else { window.makeKeyAndOrderFront(nil) }
        window.makeFirstResponder(content.grid)
        log.notice("show frame=\(NSStringFromRect(self.window.frame), privacy: .public) key=\(self.window.isKeyWindow)")
    }

    func hideCalendar() {
        log.notice("hide")
        closeEditor()
        window.orderOut(nil)
        hiddenAt = Date()
    }

    private var screens: [PopoverPlacement.Screen] {
        NSScreen.screens.map { .init(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    private func positionWindow(initial: Bool) {
        let width = content.preferredWidth
        let geometry = content.grid.model.geometry
        func agendaHeight(screenRoom: CGFloat?) -> CGFloat {
            AgendaSizing.height(content: content.agenda.contentHeight, minimum: AgendaView.emptyRowHeight,
                                geometry: geometry, screenRoom: screenRoom)
        }
        let wanted = CGSize(width: width, height: content.fixedHeight + agendaHeight(screenRoom: nil))
        let mainIndex = NSScreen.screens.firstIndex { $0 == NSScreen.main } ?? 0
        let input = PopoverPlacement.Input(
            itemFrame: status.screenFrame, itemVisible: status.isVisible, screens: screens, mainScreenIndex: mainIndex,
            windowSize: PopoverWindow.windowSize(forContent: wanted), initialPresentation: initial,
            alwaysTopRight: prefs.alwaysTopRight, previous: initial ? nil : lastPlacement,
            arrowTargetX: status.arrowTargetX)
        guard let result = PopoverPlacement.place(input) else { return }
        lastPlacement = result

        // Fit the agenda into whatever height the screen allows.
        let chrome = PopoverWindow.windowSize(forContent: .zero).height
        // Keep the window compact; the agenda scrolls beyond this. A shorter
        // grid gives its rows to the agenda, so a full window is the same
        // height every month.
        content.agendaHeight = agendaHeight(screenRoom: result.maxHeight - chrome - content.fixedHeight)
        let size = PopoverWindow.windowSize(forContent: CGSize(width: width, height: content.preferredHeight))
        let top = result.origin.y + input.windowSize.height
        let frame = CGRect(x: result.origin.x, y: top - min(size.height, result.maxHeight), width: size.width,
                           height: min(size.height, result.maxHeight))
        // Instant (no animation); the top edge and caret stay put when the
        // height changes with the month or the agenda.
        window.setFrame(frame, display: true)
        window.frameView.arrowX = result.arrowX
        content.frame = window.contentRect
        content.layoutSubtreeIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Defer so the new key window is known: keep the calendar up while
        // its own editor popover or an alert is in front.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window.isVisible, !self.keepOpenForQA else { return }
            if notification.object as? NSWindow === self.editorPanel {
                // Clicking back into the calendar keeps the editor; anywhere else closes both.
                if NSApp.modalWindow != nil || NSApp.keyWindow === self.window || NSApp.keyWindow === self.editorPanel { return }
                self.hideCalendar()
                return
            }
            if NSApp.modalWindow != nil || NSApp.keyWindow === self.window { return }
            if self.editorShown, NSApp.keyWindow === self.editorPanel { return }
            self.hideCalendar()
        }
    }

    // MARK: Navigation

    private func select(_ day: DayKey) {
        selected = day
        if day.monthKey != month { month = day.monthKey }
        refreshAll()
    }

    private func perform(_ cmd: GridCommand) {
        switch cmd {
        case .moveDays(let n): select(selected.adding(days: n))
        case .moveMonths(let n):
            month = month.adding(months: n)
            selected = GridNavigation.day(selected, movedByMonths: n)
            refreshAll()
        case .today: goToday()
        case .newEvent: newEvent(on: selected)
        case .close: hideCalendar()
        case .openSettings: openSettings(nil)
        case .joinMeeting: joinFirstActiveMeeting()
        case .toggleWeekNumbers: prefs.showWeekNumbers.toggle()
        }
    }

    @objc private func goToday() { select(today) }
    @objc private func addEvent() { newEvent(on: selected) }

    @objc private func showOptionsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Open Calendar") { [weak self] in self?.openCalendarApp() })
        menu.addItem(ClosureMenuItem(title: "Refresh") { [weak self] in
            Task { await self?.model.repository.refreshSources() }
            self?.model.reloadNow()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Settings…") { [weak self] in self?.openSettings(nil) })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    // MARK: Events

    private func newEvent(on day: DayKey) {
        guard model.access == .granted else { fixAccess(); return }
        Task {
            let defaultID = await model.repository.defaultCalendarID()
            let writable = model.writableCalendars
            let calID = writable.contains { $0.id == defaultID } ? defaultID : writable.first?.id
            guard calID != nil else {
                showAlert("No calendar can be edited", "Add or enable a writable calendar in Calendar.app, then try again.")
                return
            }
            let draft = EventDraft.new(on: day, now: Date(), calendar: model.calendar, calendarID: calID)
            presentEditor(draft, editable: true, anchor: content.grid, rect: cellRect(for: day))
        }
    }

    private func cellRect(for day: DayKey) -> CGRect {
        let g = content.grid.model
        guard let i = g.grid.index(of: day) else { return content.grid.bounds }
        return g.geometry.cellRect(index: i)
    }

    private func edit(_ e: EventSnapshot) {
        Task {
            // Demo events are not in EventKit, so there is no store to ask for a
            // draft; build one from the snapshot instead.
            let draft = model.qaDemoData ? Self.demoDraft(for: e) : await model.repository.draft(for: e)
            guard let draft else {
                showAlert("Event not found", "This event no longer exists. It may have been deleted on another device.")
                model.reloadNow()
                return
            }
            let row = content.agenda.rows.firstIndex { if case .event(let x, _) = $0 { x.id == e.id } else { false } }
            // Demo events are read-only so QA keys cannot mutate them, but the
            // docs shot should show the editor as a user sees it: with Save and
            // Delete. Nothing is saved in demo mode (the store has no event).
            let editable = e.isEditable || model.qaDemoData
            presentEditor(draft, editable: editable, anchor: content.agenda, rect: agendaRowRect(row))
        }
    }

    /// A draft for an invented event, so the QA editor dump has something to
    /// show without touching EventKit. QA only (`--qa-demo-data`).
    private static func demoDraft(for event: EventSnapshot) -> EventDraft {
        // Demo events carry a meeting link but no plain `url`; the editor shows
        // both in the same field, so fall back to the meeting.
        let url = event.url ?? event.meetingURL
        return EventDraft(eventIdentifier: event.eventIdentifier, occurrenceStart: event.occurrenceStart,
                          isRecurring: event.isRecurring, title: event.title, isAllDay: event.isAllDay,
                          start: event.start, end: event.end, calendarID: event.calendarID,
                          location: event.location ?? "", urlText: url?.absoluteString ?? "",
                          notes: event.notes ?? "")
    }

    private func agendaRowRect(_ row: Int?) -> CGRect {
        guard let row, let table = content.agenda.documentView as? NSTableView, row < table.numberOfRows else {
            return content.agenda.bounds
        }
        return content.agenda.convert(table.rect(ofRow: row), from: table)
    }

    private func presentEditor(_ draft: EventDraft, editable: Bool, anchor: NSView, rect: CGRect) {
        closeEditor()
        let c = colors
        let vc = EventEditorController(draft: draft, calendars: model.calendarGroups, editable: editable,
                                       calendar: model.calendar, colors: c)
        let repo = model.repository
        let cal = model.calendar
        vc.save = { draft, future in try await repo.save(draft, futureEvents: future, calendar: cal) }
        vc.delete = { draft, future in
            guard let id = draft.eventIdentifier, let start = draft.occurrenceStart else { return }
            try await repo.delete(eventIdentifier: id, occurrenceStart: start, futureEvents: future)
        }
        vc.finish = { [weak self] result in
            guard let self else { return }
            self.closeEditor()
            if result != .cancelled { self.model.reloadNow() }
            self.window.makeKeyAndOrderFront(nil)
            self.window.makeFirstResponder(self.content.grid)
        }

        // The same chrome as the calendar: theme fill, border, radius and shadow,
        // with the arrow pointing back at the day or agenda row.
        let panel = PopoverWindow()
        panel.appearance = NSAppearance(named: c.isDark ? .darkAqua : .aqua)
        panel.frameView.fillColor = c.background
        panel.frameView.borderColor = c.divider
        panel.fieldEditorOverride = themedFieldEditor(c)
        panel.onCancel = { [weak vc] in vc?.cancelClicked() }
        panel.delegate = self

        let body = vc.view.fittingSize
        let size = CGSize(width: ceil(body.width) + PopoverShape.arrowHeight, height: ceil(body.height))
        let inWindow = content.convert(content.convert(rect, from: anchor), to: nil)
        let anchorY = window.convertToScreen(inWindow).midY
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let place = SidePlacement.place(size: size, anchorY: anchorY, calendarFrame: window.frame, visibleFrame: visible,
                                        cornerRadius: PopoverWindow.cornerRadius)
        panel.setFrame(place.frame, display: false)
        panel.frameView.arrow = PopoverShape.Arrow(edge: place.arrowEdge, position: place.arrowPosition)
        vc.view.frame = PopoverShape.bodyRect(in: panel.frameView.bounds, arrowEdge: place.arrowEdge)
        panel.frameView.addSubview(vc.view)

        editorPanel = panel
        editorController = vc
        // Text fields need the app active to receive typing reliably.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        vc.didPresent()
        log.notice("editor frame=\(NSStringFromRect(place.frame), privacy: .public) edge=\(String(describing: place.arrowEdge), privacy: .public)")
    }

    private func closeEditor() {
        guard let panel = editorPanel else { return }
        editorController?.willClose()
        panel.delegate = nil
        panel.orderOut(nil)
        editorPanel = nil
        editorController = nil
    }

    private func confirmDelete(_ e: EventSnapshot) {
        Task {
            guard let draft = await model.repository.draft(for: e) else { return }
            presentEditor(draft, editable: e.isEditable, anchor: content.agenda,
                          rect: agendaRowRect(content.agenda.rows.firstIndex { if case .event(let x, _) = $0 { x.id == e.id } else { false } }))
            // The editor owns the confirmation and span prompt.
            self.editorController?.deleteClicked()
        }
    }

    private func join(_ e: EventSnapshot) {
        guard let url = e.meetingURL, let link = MeetingLinkParser.classify(url) else { return }
        let target = MeetingLinkParser.preferredURL(for: link) { NSWorkspace.shared.urlForApplication(toOpen: $0) != nil }
        if !NSWorkspace.shared.open(target) {
            showAlert("Couldn’t open the meeting link", "No app could open \(url.absoluteString).")
        }
        hideCalendar()
    }

    private func joinFirstActiveMeeting() {
        let events = model.events(on: today) + model.events(on: today.adding(days: 1))
        if let id = meeting.activeEventID, let e = events.first(where: { $0.id == id }) { join(e) } else { NSSound.beep() }
    }

    private func openInCalendar(_ e: EventSnapshot) {
        let id = e.eventIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? e.eventIdentifier
        if let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"), NSWorkspace.shared.open(url) {
            hideCalendar()
            return
        }
        openCalendarApp()
    }

    private func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            showAlert("Calendar not found", "The Calendar app isn’t installed on this Mac.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        hideCalendar()
    }

    @objc private func fixAccess() {
        if EventRepository.authorization == .notDetermined {
            Task { await model.start(); refreshAll() }
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
        hideCalendar()
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Settings

    @objc func openSettings(_ sender: Any?) {
        hideCalendar()
        if settings == nil { settings = SettingsWindowController(model: model) }
        settings?.show()
    }
}
