import AppKit
import GlanceCore
import SwiftUI

/// Settings: a SwiftUI form in an AppKit window, created on first use.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let state: SettingsState

    init(model: CalendarModel) {
        state = SettingsState(model: model)
        let host = NSHostingController(rootView: SettingsView(state: state))
        let window = NSWindow(contentViewController: host)
        window.title = "Glance Settings"
        // The title bar blends into the mantle background: no grey band.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        state.onThemeChange = { [weak self] in self?.applyTheme() }
        applyTheme()
    }

    /// Latte draws native controls in aqua, the dark flavours in darkAqua;
    /// Auto and System follow macOS.
    private func applyTheme() {
        guard let window else { return }
        window.appearance = ThemeColors.forcedAppearance
        window.contentViewController?.view.appearance = ThemeColors.forcedAppearance
        window.backgroundColor = state.palette.nsMantle
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func show() {
        state.reload()
        NSApp.activate()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func showHotKeyError(_ message: String) { state.hotKeyError = message }

    func windowWillClose(_ notification: Notification) {
        // Make sure a recorder never leaves the hotkey unregistered.
        HotKeyCenter.shared.register(Preferences.shared.hotKey)
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
    var onThemeChange: (() -> Void)?
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

struct SettingsView: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        TabView {
            GeneralSettings(state: state).tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(state: state).tabItem { Label("Appearance", systemImage: "paintpalette") }
            CalendarSettings(state: state).tabItem { Label("Calendars", systemImage: "calendar") }
        }
        // Grouped forms in a TabView have no intrinsic height; size explicitly.
        .frame(width: 500, height: 560)
        .environment(\.palette, state.palette)
        .tint(state.palette.accent)
        .foregroundStyle(state.palette.text)
        .background(state.palette.mantle)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
        Form {
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
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var orderedWeekdays: [Int] {
        let first = Preferences.shared.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

private struct CalendarSettings: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
