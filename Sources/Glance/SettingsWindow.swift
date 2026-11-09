import AppKit
import GlanceCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, calendars
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .calendars: "Calendars"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .calendars: "calendar"
        }
    }
}

/// Settings: SwiftUI tabs in an AppKit window with Settings-style toolbar
/// tabs. The window takes each tab's natural height and animates between
/// them; a tab only scrolls when it can't fit on screen.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    static let contentWidth: CGFloat = 520
    private let state: SettingsState

    init(model: CalendarModel) {
        state = SettingsState(model: model)
        let host = NSHostingController(rootView: SettingsView(state: state))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 400),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.contentViewController = host
        // The title bar blends into the mantle background: no grey band.
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "GlanceSettings")
        toolbar.delegate = self
        // Each tab is a view-based item so the selected one can take the accent.
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = Set(SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) })
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        select(.general, animate: false)

        state.onThemeChange = { [weak self] in self?.applyTheme() }
        state.onContentHeight = { [weak self] _ in self?.fitWindow(animate: true) }
        applyTheme()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func show() {
        state.reload()
        NSApp.activate()
        if window?.isVisible != true {
            fitWindow(animate: false)
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func showHotKeyError(_ message: String) { state.hotKeyError = message }

    func selectTab(named name: String) {
        if let tab = SettingsTab(rawValue: name) { select(tab, animate: true) }
    }

    func windowWillClose(_ notification: Notification) {
        // Make sure a recorder never leaves the hotkey unregistered.
        HotKeyCenter.shared.register(Preferences.shared.hotKey)
    }

    /// Latte draws native controls in aqua, the dark flavours in darkAqua;
    /// Auto and System follow macOS.
    private func applyTheme() {
        guard let window else { return }
        window.appearance = ThemeColors.forcedAppearance
        window.contentViewController?.view.appearance = ThemeColors.forcedAppearance
        window.backgroundColor = state.palette.nsMantle
        refreshToolbarImages()
    }

    // MARK: Tabs

    private func select(_ tab: SettingsTab, animate: Bool) {
        state.tab = tab
        window?.title = tab.title
        refreshToolbarImages()
        // The new tab reports its height once laid out; fitWindow follows.
        if !animate { fitWindow(animate: false) }
    }

    private func tabClicked(_ tab: SettingsTab) {
        guard tab != state.tab else { return }
        select(tab, animate: true)
    }

    /// Tab views observe the state, so they restyle themselves.
    private func refreshToolbarImages() {}

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    nonisolated func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                             willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            guard let tab = SettingsTab(rawValue: id.rawValue) else { return nil }
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = tab.title
            let view = NSHostingView(rootView: SettingsTabButton(tab: tab, state: state) { [weak self] in self?.tabClicked(tab) })
            view.frame.size = view.fittingSize
            item.view = view
            return item
        }
    }

    // MARK: Sizing

    /// Height of the title bar and toolbar above the content.
    private var chromeHeight: CGFloat {
        guard let window else { return 0 }
        return window.frame.height - window.contentLayoutRect.height
    }

    private func fitWindow(animate: Bool) {
        guard let window, let natural = state.contentHeights[state.tab] else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let fit = SettingsModel.contentHeight(natural: natural, available: visible.height - chromeHeight - 40)
        if state.scrolls != fit.scrolls { state.scrolls = fit.scrolls }
        let height = fit.height + chromeHeight
        var frame = window.frame
        guard abs(frame.height - height) > 0.5 || abs(frame.width - Self.contentWidth) > 0.5 else { return }
        // Keep the top edge still, like System Settings.
        frame.origin.y = frame.maxY - height
        frame.size = CGSize(width: Self.contentWidth, height: height)
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}

@MainActor
final class SettingsState: ObservableObject {
    let model: CalendarModel
    private let prefs = Preferences.shared

    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var loginError: String?
    @Published var hotKeyError: String?
    @Published var groups: [CalendarSourceGroup] = []
    @Published var selected: Set<String> = []
    @Published var accessGranted = false
    @Published private(set) var palette = SettingsPalette.current()
    @Published var tab: SettingsTab = .general
    /// Whether the current tab is taller than the screen allows.
    @Published var scrolls = false
    private(set) var contentHeights: [SettingsTab: CGFloat] = [:]
    var onThemeChange: (() -> Void)?
    var onContentHeight: ((SettingsTab) -> Void)?

    func reportHeight(_ h: CGFloat, for tab: SettingsTab) {
        guard h > 0, abs((contentHeights[tab] ?? 0) - h) > 0.5 else { return }
        contentHeights[tab] = h
        if tab == self.tab { onContentHeight?(tab) }
    }
    private var observers: [Any] = []

    init(model: CalendarModel) {
        self.model = model
        reload()
        // Follow theme changes live, and macOS light/dark for Auto and System.
        observers.append(NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] n in
            let key = n.userInfo?["key"] as? String
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
                if key == "theme" { self?.refreshPalette() }
            }
        })
        observers.append(NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshPalette() }
        })
    }

    private func refreshPalette() {
        let p = SettingsPalette.current()
        if p != palette { palette = p }
        onThemeChange?()
    }

    func reload() {
        launchAtLogin = LoginItem.isEnabled
        loginError = LoginItem.needsApproval
            ? "macOS needs your approval: turn on Glance in System Settings › General › Login Items & Extensions." : nil
        accessGranted = model.access == .granted
        groups = model.calendarGroups
        selected = prefs.selectedCalendarIDs ?? Set(model.calendars.map(\.id))
        Task {
            await model.reloadCalendars()
            groups = model.calendarGroups
            selected = prefs.selectedCalendarIDs ?? Set(model.calendars.map(\.id))
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        loginError = LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }

    func setCalendar(_ id: String, on: Bool) {
        if on { selected.insert(id) } else { selected.remove(id) }
        let all = Set(model.calendars.map(\.id))
        prefs.selectedCalendarIDs = selected == all ? nil : selected
    }

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { [prefs] in prefs[keyPath: keyPath] },
                set: { [prefs, weak self] in prefs[keyPath: keyPath] = $0; self?.objectWillChange.send() })
    }
}

/// A Settings toolbar tab: SF Symbol over its label, the selected one in the
/// accent colour on a surface0 pill.
struct SettingsTabButton: View {
    let tab: SettingsTab
    @ObservedObject var state: SettingsState
    let action: () -> Void

    var body: some View {
        let p = state.palette
        let selected = state.tab == tab
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol).font(.system(size: 17, weight: .regular)).frame(height: 20)
                Text(tab.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? p.accent : p.subtext0)
            .frame(width: 78, height: 46)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? p.surface0 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SettingsView: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        ScrollView(.vertical) {
            content
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .frame(width: SettingsWindowController.contentWidth, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                })
        }
        .scrollIndicators(state.scrolls ? .visible : .never)
        .scrollDisabled(!state.scrolls)
        .onPreferenceChange(ContentHeightKey.self) { h in
            MainActor.assumeIsolated { state.reportHeight(h, for: state.tab) }
        }
        .id(state.tab)
        .environment(\.palette, state.palette)
        .tint(state.palette.accent)
        .foregroundStyle(state.palette.text)
        .background(state.palette.mantle)
    }

    @ViewBuilder private var content: some View {
        switch state.tab {
        case .general: GeneralSettings(state: state)
        case .appearance: AppearanceSettings(state: state)
        case .calendars: CalendarSettings(state: state)
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Section {
                Toggle("Open at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                if let error = state.loginError {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Open Login Items") { LoginItem.openSystemSettings() }.controlSize(.small)
                    }
                }
                LabeledContent("Show or hide calendar") {
                    HotKeyRecorder(combo: state.binding(\.hotKey), error: $state.hotKeyError)
                        .frame(width: 160, height: 22)
                }
                if let error = state.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Menu bar") {
                Picker("Icon", selection: state.binding(\.iconStyle)) {
                    Text("Outline").tag(IconLayout.Style.outline)
                    Text("Filled").tag(IconLayout.Style.filled)
                }
                Toggle("Hide the date icon", isOn: state.binding(\.hideIcon))
                ClockFormatField(format: state.binding(\.clockFormat))
                Toggle("Show a meeting indicator", isOn: state.binding(\.showMeetingIndicator))
                Stepper(value: state.binding(\.meetingLeadMinutes), in: 0...30) {
                    Text("Show it \(Preferences.shared.meetingLeadMinutes) min before a call starts")
                }
                .disabled(!Preferences.shared.showMeetingIndicator)
                Toggle("Always open at the top right of the screen", isOn: state.binding(\.alwaysTopRight))
            }
            Section("Agenda") {
                Stepper(value: state.binding(\.agendaDays), in: 1...31) {
                    Text("Show \(Preferences.shared.agendaDays) day\(Preferences.shared.agendaDays == 1 ? "" : "s") of events")
                }
                Toggle("Show days without events", isOn: state.binding(\.showEmptyAgendaDays))
            }
        }

    }
}

private struct ClockFormatField: View {
    @Binding var format: String
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Clock format", text: $text, prompt: Text("e.g. EEE h:mm a"))
                .onSubmit { format = text }
                .onChange(of: text) { _, new in format = new }
            Text(preview).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { text = format }
    }

    private var preview: String {
        let f = ClockFormat(text)
        if f.isEmpty { return "Leave empty to show only the date icon. Uses Unicode date patterns: EEE d MMM h:mm a" }
        let df = DateFormatter()
        df.dateFormat = text
        return "Preview: " + df.string(from: Date())
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var state: SettingsState
    private let weekdays = Calendar.autoupdatingCurrent.weekdaySymbols

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Theme", selection: state.binding(\.theme)) {
                ForEach(ThemeChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Week starts on", selection: state.binding(\.firstWeekdaySetting)) {
                Text("System (\(weekdays[Calendar.autoupdatingCurrent.firstWeekday - 1]))").tag(0)
                ForEach(1...7, id: \.self) { Text(weekdays[$0 - 1]).tag($0) }
            }
            Toggle("Show week numbers", isOn: state.binding(\.showWeekNumbers))
            Toggle("Show event dots", isOn: state.binding(\.showEventDots))
            LabeledContent("Highlight") {
                HStack(spacing: 4) {
                    ForEach(orderedWeekdays, id: \.self) { wd in
                        Toggle(String(weekdays[wd - 1].prefix(3)), isOn: Binding(
                            get: { Preferences.shared.highlightedWeekdays.contains(weekday: wd) },
                            set: { on in
                                var s = Preferences.shared.highlightedWeekdays
                                if on { s.insert(WeekdaySet(weekdays: [wd])) } else { s.remove(WeekdaySet(weekdays: [wd])) }
                                Preferences.shared.highlightedWeekdays = s
                                state.objectWillChange.send()
                            }))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
        }

    }

    private var orderedWeekdays: [Int] {
        let first = Preferences.shared.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

private struct CalendarSettings: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.accessGranted {
                Text("Glance doesn’t have access to your calendars. Turn on Full Access for Glance in System Settings › Privacy & Security › Calendars.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else if state.groups.isEmpty {
                Text("No calendars found. Add an account in Calendar.app or System Settings › Internet Accounts.")
                    .foregroundStyle(.secondary)
            }
            ForEach(state.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.calendars) { cal in
                        Toggle(isOn: Binding(get: { state.selected.contains(cal.id) },
                                             set: { state.setCalendar(cal.id, on: $0) })) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: NSColor(rgba: cal.color)))
                                    .frame(width: 10, height: 10)
                                Text(cal.title)
                            }
                        }
                    }
                }
            }
        }

    }
}

/// Click, then press a shortcut. Esc cancels, Delete clears.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    @Binding var error: String?

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onChange = { combo = $0; error = nil }
        v.onError = { error = $0 }
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.combo = combo
    }

    @MainActor
    final class RecorderView: NSView {
        var combo: KeyCombo? { didSet { needsDisplay = true } }
        var onChange: ((KeyCombo?) -> Void)?
        var onError: ((String) -> Void)?
        private var recording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var focusRingMaskBounds: NSRect { bounds }
        override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill() }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            recording = true
            // Release the current hotkey so pressing it records instead of firing.
            HotKeyCenter.shared.unregister()
        }

        override func resignFirstResponder() -> Bool {
            stopRecording()
            return super.resignFirstResponder()
        }

        private func stopRecording() {
            guard recording else { return }
            recording = false
            HotKeyCenter.shared.register(Preferences.shared.hotKey)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53, flags.isEmpty { stopRecording(); return }             // Esc
            if event.keyCode == 51 || event.keyCode == 117, flags.isEmpty {               // Delete
                recording = false
                onChange?(nil)
                return
            }
            let c = KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: KeyboardLayout.carbonModifiers(flags))
            guard c.isValidGlobalHotKey else {
                onError?("Add ⌘, ⌥ or ⌃ to the shortcut so it doesn’t interfere with typing.")
                return
            }
            recording = false
            onChange?(c)
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            let text: String
            if recording { text = "Type shortcut…" }
            else if let combo { text = combo.displayString(characterForKeyCode: KeyboardLayout.character(for:)) }
            else { text = "Click to record" }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: (recording || combo == nil) ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
    }
}
