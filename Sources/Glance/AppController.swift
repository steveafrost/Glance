import AppKit
import GlanceCore
import os

private let log = Logger(subsystem: "com.steveafrost.Glance", category: "app")

/// Wires the status item, calendar window, data model, timers and settings together.
@MainActor
final class AppController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let prefs = Preferences.shared
    private let model = CalendarModel()
    private let status = StatusItemController()
    private let window = PopoverWindow()
    private let tooltip = TooltipPanel()
    private let content: CalendarContentView
    private var settings: SettingsWindowController?
    private var editor: NSPopover?

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

    override init() {
        let cal = Calendar.autoupdatingCurrent
        let t = DayKey(date: Date(), calendar: cal)
        today = t
        selected = t
        month = t.monthKey
        let grid = MonthGridView(model: .init(grid: MonthGrid(month: t.monthKey, firstWeekday: Preferences.shared.firstWeekday),
                                              selected: t, today: t, highlighted: Preferences.shared.highlightedWeekdays,
                                              dots: [:], geometry: GridGeometry(showsWeekNumbers: Preferences.shared.showWeekNumbers)))
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
        if args.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showCalendar() }
        }
    }

    private func sendQAKeys(_ script: String) {
        let codes: [String: (UInt16, String)] = [
            "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "down": (125, "\u{F701}"), "up": (126, "\u{F700}"),
            "return": (36, "\r"), "escape": (53, "\u{1b}"), "space": (49, " "), "comma": (43, ","),
        ]
        var delay = 0.0
        for token in script.split(separator: ",") {
            var parts = token.split(separator: "+").map(String.init)
            let key = parts.removeLast()
            var flags: NSEvent.ModifierFlags = []
            if parts.contains("shift") { flags.insert(.shift) }
            if parts.contains("cmd") { flags.insert(.command) }
            let (code, chars) = codes[key] ?? (0, key)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                                          windowNumber: self.window.windowNumber, context: nil, characters: chars,
                                                          charactersIgnoringModifiers: flags.contains(.shift) ? chars.uppercased() : chars,
                                                          isARepeat: false, keyCode: code) else { return }
                log.notice("qa key \(String(token), privacy: .public)")
                self.window.sendEvent(e)
                log.notice("qa state month=\(self.month.description, privacy: .public) selected=\(self.selected.description, privacy: .public) visible=\(self.window.isVisible) editor=\(self.editor?.isShown == true) settings=\(self.settings?.window?.isVisible == true)")
            }
            delay += 0.4
        }
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
        grid.onHover = { [weak self] day, rect in self?.hover(day, rect: rect) }

        content.prevButton.target = self
        content.prevButton.action = #selector(prevMonth)
        content.nextButton.target = self
        content.nextButton.action = #selector(nextMonth)
        content.todayButton.target = self
        content.todayButton.action = #selector(goToday)
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
        status.setMeetingActive(state.activeEventID != nil)
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
        case "hideIcon", "iconStyle", "showMeetingIndicator": status.update()
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
        tooltip.appearance = appearance
        let effective = appearance ?? NSApp.effectiveAppearance
        var colors: ThemeColors!
        withAppearance(effective) { colors = ThemeColors.current(for: effective) }
        window.frameView.fillColor = colors.background
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
        let geometry = GridGeometry(showsWeekNumbers: prefs.showWeekNumbers)
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
        if window.isVisible { positionWindow(initial: false) }
    }

    // MARK: Window

    func toggleCalendar() {
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
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(content.grid)
        log.notice("show frame=\(NSStringFromRect(self.window.frame), privacy: .public) key=\(self.window.isKeyWindow)")
    }

    func hideCalendar() {
        log.notice("hide")
        editor?.close()
        tooltip.cancel()
        window.orderOut(nil)
        hiddenAt = Date()
    }

    private var screens: [PopoverPlacement.Screen] {
        NSScreen.screens.map { .init(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    private func positionWindow(initial: Bool) {
        let width = content.preferredWidth
        let wanted = CGSize(width: width, height: content.fixedHeight + min(max(content.agenda.contentHeight, AgendaView.emptyRowHeight), AgendaView.maxHeight))
        let mainIndex = NSScreen.screens.firstIndex { $0 == NSScreen.main } ?? 0
        let input = PopoverPlacement.Input(
            itemFrame: status.screenFrame, itemVisible: status.isVisible, screens: screens, mainScreenIndex: mainIndex,
            windowSize: PopoverWindow.windowSize(forContent: wanted), initialPresentation: initial,
            alwaysTopRight: prefs.alwaysTopRight, previous: initial ? nil : lastPlacement)
        guard let result = PopoverPlacement.place(input) else { return }
        lastPlacement = result

        // Fit the agenda into whatever height the screen allows.
        let chrome = PopoverWindow.windowSize(forContent: .zero).height
        // Keep the window compact; the agenda scrolls beyond this.
        let maxAgenda = min(AgendaView.maxHeight, max(60, result.maxHeight - chrome - content.fixedHeight))
        content.agendaHeight = min(max(content.agenda.contentHeight, AgendaView.emptyRowHeight), maxAgenda)
        let size = PopoverWindow.windowSize(forContent: CGSize(width: width, height: content.preferredHeight))
        let top = result.origin.y + input.windowSize.height
        let frame = CGRect(x: result.origin.x, y: top - min(size.height, result.maxHeight), width: size.width,
                           height: min(size.height, result.maxHeight))
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
            if self.editor?.isShown == true || NSApp.modalWindow != nil || NSApp.keyWindow === self.window { return }
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

    @objc private func prevMonth() { perform(.moveMonths(-1)) }
    @objc private func nextMonth() { perform(.moveMonths(1)) }
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

    private func hover(_ day: DayKey?, rect: CGRect) {
        guard let day, window.isVisible, editor?.isShown != true else { tooltip.cancel(); return }
        let events = model.events(on: day)
        let lines = events.map {
            TooltipView.Line(time: Agenda.timeText(for: $0, on: day, calendar: model.calendar, locale: .autoupdatingCurrent),
                             title: $0.title, color: NSColor(rgba: $0.color))
        }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let screenRect = window.convertToScreen(rect)
        tooltip.schedule(lines: lines, title: f.string(from: day.startDate(in: model.calendar)), near: screenRect,
                         appearance: window.appearance, colors: colors)
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
            guard let draft = await model.repository.draft(for: e) else {
                showAlert("Event not found", "This event no longer exists. It may have been deleted on another device.")
                model.reloadNow()
                return
            }
            let row = content.agenda.rows.firstIndex { if case .event(let x, _) = $0 { x.id == e.id } else { false } }
            presentEditor(draft, editable: e.isEditable, anchor: content.agenda, rect: agendaRowRect(row))
        }
    }

    private func agendaRowRect(_ row: Int?) -> CGRect {
        guard let row, let table = content.agenda.documentView as? NSTableView, row < table.numberOfRows else {
            return content.agenda.bounds
        }
        return content.agenda.convert(table.rect(ofRow: row), from: table)
    }

    private func presentEditor(_ draft: EventDraft, editable: Bool, anchor: NSView, rect: CGRect) {
        editor?.close()
        tooltip.cancel()
        let vc = EventEditorController(draft: draft, calendars: model.calendarGroups, editable: editable, calendar: model.calendar)
        let repo = model.repository
        let cal = model.calendar
        vc.save = { draft, future in try await repo.save(draft, futureEvents: future, calendar: cal) }
        vc.delete = { draft, future in
            guard let id = draft.eventIdentifier, let start = draft.occurrenceStart else { return }
            try await repo.delete(eventIdentifier: id, occurrenceStart: start, futureEvents: future)
        }
        vc.finish = { [weak self] result in
            self?.editor?.close()
            if result != .cancelled { self?.model.reloadNow() }
            self?.window.makeKeyAndOrderFront(nil)
            self?.window.makeFirstResponder(self?.content.grid)
        }
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .applicationDefined
        popover.appearance = window.appearance
        popover.delegate = self
        editor = popover
        // Text fields need the app active to receive typing reliably.
        NSApp.activate()
        // Anchor at the window's left edge, level with the day or row, so the
        // editor sits beside the calendar instead of covering it.
        var r = content.convert(rect, from: anchor)
        r.origin.x = 0
        r.size.width = 1
        popover.show(relativeTo: r, of: content, preferredEdge: .minX)
    }

    func popoverDidClose(_ notification: Notification) {
        if (notification.object as? NSPopover) === editor { editor = nil }
    }

    private func confirmDelete(_ e: EventSnapshot) {
        Task {
            guard let draft = await model.repository.draft(for: e) else { return }
            presentEditor(draft, editable: e.isEditable, anchor: content.agenda,
                          rect: agendaRowRect(content.agenda.rows.firstIndex { if case .event(let x, _) = $0 { x.id == e.id } else { false } }))
            // The editor owns the confirmation and span prompt.
            (editor?.contentViewController as? EventEditorController)?.deleteClicked()
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
