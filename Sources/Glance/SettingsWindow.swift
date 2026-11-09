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
    @Environment(\.palette) private var p
    private var prefs: Preferences { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection {
                SettingsRow(label: "Open at login", caption: state.loginError) {
                    HStack(spacing: 8) {
                        if state.loginError != nil {
                            AccentLink(title: "Open Login Items") { LoginItem.openSystemSettings() }
                        }
                        ThemedSwitch(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                    }
                }
                SettingsRow(label: "Show or hide calendar", caption: state.hotKeyError ?? "A shortcut that works in any app") {
                    HotKeyField(combo: state.binding(\.hotKey), error: $state.hotKeyError)
                }
            }

            SettingsSection(title: "Menu bar") {
                SettingsRow(label: "Icon") {
                    ThemedMenuPicker(selection: iconChoice, options: SettingsModel.IconChoice.allCases.map { ($0, $0.title) },
                                     width: 120)
                }
                if SettingsModel.showsEmptyItemWarning(icon: iconChoice.wrappedValue, clockPattern: prefs.clockFormat) {
                    SettingsNote(text: "With no icon and no clock there’s nothing to click, so Glance keeps showing the date icon.")
                }
                ClockRows(state: state)
                SettingsRow(label: "Meeting indicator", caption: "A camera beside the icon while a call is on or about to start") {
                    ThemedSwitch(isOn: state.binding(\.showMeetingIndicator))
                }
                SettingsRow(label: "Meeting indicator lead time", disabled: !prefs.showMeetingIndicator) {
                    ThemedStepper(value: state.binding(\.meetingLeadMinutes), range: 0...30, format: SettingsModel.minutes)
                }
                SettingsRow(label: "Open at the top right of the screen", caption: "Instead of under the menu bar icon") {
                    ThemedSwitch(isOn: state.binding(\.alwaysTopRight))
                }
            }

            SettingsSection(title: "Agenda") {
                SettingsRow(label: "Agenda length") {
                    ThemedStepper(value: state.binding(\.agendaDays), range: 1...31, format: SettingsModel.days)
                }
                SettingsRow(label: "Show days without events") {
                    ThemedSwitch(isOn: state.binding(\.showEmptyAgendaDays))
                }
            }
        }
    }

    private var iconChoice: Binding<SettingsModel.IconChoice> {
        Binding(get: { SettingsModel.IconChoice(style: prefs.iconStyle, hidden: prefs.hideIcon) },
                set: { choice in
                    prefs.iconStyle = choice.style(keeping: prefs.iconStyle)
                    prefs.hideIcon = choice.hidesIcon
                    state.objectWillChange.send()
                })
    }
}

/// Clock presets with a live preview; the raw pattern only for Custom.
private struct ClockRows: View {
    @ObservedObject var state: SettingsState
    @State private var custom = SettingsModel.ClockPreset.matching(Preferences.shared.clockFormat) == .custom
    @State private var text = Preferences.shared.clockFormat
    @Environment(\.palette) private var p

    private var pattern: String { Preferences.shared.clockFormat }

    var body: some View {
        // The caption previews what the menu bar shows, ticking while visible.
        TimelineView(.periodic(from: .now, by: ClockFormat(pattern).usesSeconds ? 1 : 15)) { ctx in
            SettingsRow(label: "Clock", caption: Self.preview(pattern, at: ctx.date)) {
                ThemedMenuPicker(selection: preset, options: SettingsModel.ClockPreset.allCases.map { ($0, title($0)) },
                                 width: 170)
            }
        }
        if custom {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pattern").font(.system(size: 13)).foregroundStyle(p.text)
                    Spacer()
                    ThemedTextField(placeholder: "EEE h:mm a", text: $text, width: 200, monospaced: true)
                        .onChange(of: text) { _, new in Preferences.shared.clockFormat = new }
                }
                Text("Unicode date pattern: EEE weekday, d day, MMM month, h:mm a time, HH:mm 24-hour, ss seconds.")
                    .font(.system(size: 11)).foregroundStyle(p.subtext0).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var preset: Binding<SettingsModel.ClockPreset> {
        Binding(get: { custom ? .custom : SettingsModel.ClockPreset.matching(pattern) },
                set: { new in
                    if new == .custom {
                        custom = true
                        text = pattern
                    } else {
                        custom = false
                        Preferences.shared.clockFormat = new.pattern ?? ""
                        text = Preferences.shared.clockFormat
                    }
                    state.objectWillChange.send()
                })
    }

    static func preview(_ pattern: String, at now: Date) -> String {
        if ClockFormat(pattern).isEmpty { return "No clock text" }
        let df = DateFormatter()
        df.locale = .autoupdatingCurrent
        df.dateFormat = pattern
        return "Shows “\(df.string(from: now))”"
    }

    private func title(_ preset: SettingsModel.ClockPreset) -> String {
        let df = DateFormatter()
        df.locale = .autoupdatingCurrent
        let sample = SettingsModel.ClockPreset.sampleDate(calendar: .autoupdatingCurrent)
        return preset.title { df.dateFormat = $0; return df.string(from: sample) }
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var state: SettingsState
    @Environment(\.palette) private var p
    private let weekdays = Calendar.autoupdatingCurrent.weekdaySymbols
    private let shortWeekdays = Calendar.autoupdatingCurrent.shortWeekdaySymbols
    private var prefs: Preferences { .shared }

    private var mode: SettingsModel.ThemeMode { .init(prefs.theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Theme") {
                HStack(spacing: 10) {
                    ForEach(CatppuccinFlavor.allCases, id: \.self) { flavor in
                        FlavorSwatch(flavor: flavor, ringed: mode.ringedFlavor(isDarkMode: isDarkMode) == flavor,
                                     dimmed: mode == .systemColors) {
                            setTheme(SettingsModel.ThemeMode.flavor(flavor).choice)
                        }
                    }
                }
                .padding(12)
                SettingsRow(label: "Match macOS appearance", caption: "Latte in Light mode, Mocha in Dark mode") {
                    ThemedSwitch(isOn: Binding(get: { mode == .matchSystem },
                                               set: { setTheme($0 ? .catppuccinAuto : flavorChoice) }))
                }
                SettingsRow(label: "Use system colours", caption: "Native macOS colours instead of Catppuccin") {
                    ThemedSwitch(isOn: Binding(get: { mode == .systemColors },
                                               set: { setTheme($0 ? .system : flavorChoice) }))
                }
            }

            SettingsSection(title: "Calendar") {
                SettingsRow(label: "Week starts on") {
                    ThemedMenuPicker(selection: state.binding(\.firstWeekdaySetting),
                                     options: [(0, "System (\(weekdays[Calendar.autoupdatingCurrent.firstWeekday - 1]))")]
                                         + (1...7).map { ($0, weekdays[$0 - 1]) },
                                     width: 160)
                }
                SettingsRow(label: "Highlighted days", caption: "Shaded columns in the grid") {
                    HStack(spacing: 4) {
                        ForEach(SettingsModel.orderedWeekdays(firstWeekday: prefs.firstWeekday), id: \.self) { wd in
                            DayChip(title: shortWeekdays[wd - 1], isOn: highlighted(wd))
                        }
                    }
                }
                SettingsRow(label: "Show week numbers") { ThemedSwitch(isOn: state.binding(\.showWeekNumbers)) }
                SettingsRow(label: "Show event dots", caption: "Coloured dots under days with events") {
                    ThemedSwitch(isOn: state.binding(\.showEventDots))
                }
            }
        }
    }

    private var isDarkMode: Bool { NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    /// Turning a mode off lands on the flavour that's showing now.
    private var flavorChoice: ThemeChoice {
        SettingsModel.ThemeMode.flavor(mode.ringedFlavor(isDarkMode: isDarkMode) ?? (isDarkMode ? .mocha : .latte)).choice
    }

    private func setTheme(_ choice: ThemeChoice) {
        prefs.theme = choice
        state.objectWillChange.send()
    }

    private func highlighted(_ wd: Int) -> Binding<Bool> {
        Binding(get: { prefs.highlightedWeekdays.contains(weekday: wd) },
                set: { on in
                    var s = prefs.highlightedWeekdays
                    if on { s.insert(WeekdaySet(weekdays: [wd])) } else { s.remove(WeekdaySet(weekdays: [wd])) }
                    prefs.highlightedWeekdays = s
                    state.objectWillChange.send()
                })
    }
}

/// A flavour card: a miniature of the calendar in that flavour's colours,
/// ringed in the accent colour when selected.
private struct FlavorSwatch: View {
    let flavor: CatppuccinFlavor
    let ringed: Bool
    let dimmed: Bool
    let action: () -> Void
    @Environment(\.palette) private var p

    private func col(_ hex: UInt32) -> Color { Color(nsColor: NSColor(rgba: RGBA(hex: hex))) }

    var body: some View {
        let c = flavor.colors
        Button(action: action) {
            VStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach([c.mauve, c.blue, c.green, c.peach, c.red], id: \.self) { hex in
                            Circle().fill(col(hex)).frame(width: 9, height: 9)
                        }
                    }
                    RoundedRectangle(cornerRadius: 2).fill(col(c.text)).frame(width: 54, height: 5)
                    RoundedRectangle(cornerRadius: 2).fill(col(c.subtext0)).frame(width: 38, height: 5)
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i == 2 ? col(c.mauve) : col(c.surface0))
                                .frame(width: 11, height: 9)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(col(c.base)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(col(c.surface0), lineWidth: 1))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ringed ? p.accent : .clear, lineWidth: 2))
                Text(flavor.displayName).font(.system(size: 12, weight: ringed ? .semibold : .regular))
                    .foregroundStyle(ringed ? p.text : p.subtext0)
            }
            .opacity(dimmed ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Catppuccin \(flavor.displayName)"))
        .accessibilityAddTraits(ringed ? .isSelected : [])
    }
}

/// A toggleable weekday chip: accent when on, surface0 when off.
private struct DayChip: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.palette) private var p

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(title).font(.system(size: 11, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? p.onAccent : p.subtext0)
                .frame(width: 34, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isOn ? p.accent : p.surface0))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(isOn ? .clear : p.surface1, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
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

/// The hotkey recorder with an inline clear button.
private struct HotKeyField: View {
    @Binding var combo: KeyCombo?
    @Binding var error: String?
    @State private var recording = false
    @Environment(\.palette) private var p

    var body: some View {
        HotKeyRecorder(combo: $combo, error: $error, recording: $recording, palette: p)
            .frame(width: 160, height: 24)
            .overlay(alignment: .trailing) {
                if combo != nil && !recording {
                    Button { combo = nil; error = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(p.overlay0)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear the shortcut")
                    .padding(.trailing, 2)
                }
            }
    }
}

/// Click, then press a shortcut. Esc cancels, Delete clears.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    @Binding var error: String?
    @Binding var recording: Bool
    var palette: SettingsPalette

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onChange = { combo = $0; error = nil }
        v.onError = { error = $0 }
        v.onRecording = { recording = $0 }
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.combo = combo
        v.palette = palette
    }

    @MainActor
    final class RecorderView: NSView {
        var combo: KeyCombo? { didSet { needsDisplay = true } }
        var palette: SettingsPalette? { didSet { needsDisplay = true } }
        var onChange: ((KeyCombo?) -> Void)?
        var onError: ((String) -> Void)?
        var onRecording: ((Bool) -> Void)?
        private var recording = false { didSet { needsDisplay = true; if recording != oldValue { onRecording?(recording) } } }

        override var acceptsFirstResponder: Bool { true }
        override var focusRingType: NSFocusRingType { get { .none } set {} }

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
            guard recording else {
                if event.keyCode == 49 || event.keyCode == 36 { mouseDown(with: event) } else { super.keyDown(with: event) }
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53, flags.isEmpty { stopRecording(); return }             // Esc
            if event.keyCode == 51 || event.keyCode == 117, flags.isEmpty {               // Delete
                stopRecording()
                onChange?(nil)
                return
            }
            let c = KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: KeyboardLayout.carbonModifiers(flags))
            guard c.isValidGlobalHotKey else {
                onError?("Add ⌘, ⌥ or ⌃ so the shortcut doesn’t interfere with typing.")
                return
            }
            recording = false
            onChange?(c)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let p = palette else { return }
            let ring: CGFloat = recording ? 2 : 1
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: ring / 2, dy: ring / 2), xRadius: 6, yRadius: 6)
            NSColor(p.surface0).setFill()
            path.fill()
            NSColor(recording ? p.accent : p.surface1).setStroke()
            path.lineWidth = ring
            path.stroke()
            let text: String
            let colour: NSColor
            if recording { text = "Press keys…"; colour = NSColor(p.accent) }
            else if let combo { text = combo.displayString(characterForKeyCode: KeyboardLayout.character(for:)); colour = NSColor(p.text) }
            else { text = "Record Shortcut"; colour = NSColor(p.subtext0) }
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: combo != nil && !recording ? .medium : .regular),
                                                        .foregroundColor: colour]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
    }
}
