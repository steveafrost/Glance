import AppKit
import GlanceCore

/// The menu bar item: date icon, optional clock text, meeting indicator.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    let item: NSStatusItem
    var onClick: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let prefs = Preferences.shared
    private let formatter = DateFormatter()
    private(set) var clock = ClockFormat("")
    private var clockWidth: CGFloat = 0
    private var meetingActive = false
    private var lastPlacement: IconLayout.Placement?
    private var observers: [any NSObjectProtocol] = []

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = "GlanceStatusItem"
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            (button.cell as? NSButtonCell)?.highlightsBy = []
            button.imageScaling = .scaleNone
        }
        // The button's window moves between displays (and changes backing
        // scale) as the menu bar does; re-place the icon when it does.
        if let window = item.button?.window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didChangeBackingPropertiesNotification, NSWindow.didChangeScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshIfPlacementChanged() }
                })
            }
        }
        configureClock()
    }

    // MARK: Updating

    func configureClock() {
        clock = ClockFormat(prefs.clockFormat)
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = clock.isEmpty ? "" : clock.pattern
        clockWidth = clock.isEmpty ? 0 : measureClockWidth()
        update()
    }

    func setMeetingActive(_ active: Bool) {
        guard active != meetingActive else { return }
        meetingActive = active
        update()
    }

    /// Redraw the icon and clock text for "now".
    func update(now: Date = Date()) {
        guard let button = item.button else { return }
        let showMeeting = meetingActive && prefs.showMeetingIndicator
        let day = Calendar.autoupdatingCurrent.component(.day, from: now)
        let iconText: String? = prefs.hideIcon ? nil : String(day)
        let placement = currentPlacement()
        lastPlacement = placement

        if iconText != nil || showMeeting {
            button.image = IconRenderer.image(text: iconText, style: prefs.iconStyle, meeting: showMeeting,
                                              placement: placement, opticalOffset: prefs.iconOpticalOffset)
        } else {
            button.image = nil
        }

        var title = ""
        if !clock.isEmpty {
            title = formatter.string(from: now)
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: clockFont])
            button.imagePosition = button.image == nil ? .noImage : .imageLeading
            button.imageHugsTitle = true
            // A fixed length keeps the item (and everything to its left) from jittering.
            item.length = fixedLength(imageWidth: button.image?.size.width ?? 0)
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            item.length = NSStatusItem.variableLength
            if button.image == nil {
                // Nothing to show: keep a minimal glyph so the item stays clickable.
                button.image = IconRenderer.image(text: String(day), style: prefs.iconStyle, meeting: false,
                                                  placement: placement, opticalOffset: prefs.iconOpticalOffset)
            }
        }

        var label = "Glance"
        if let iconText { label += ", \(iconText)" }
        if !title.isEmpty { label += ", \(title)" }
        if showMeeting { label += ", meeting now" }
        button.setAccessibilityLabel(label)
        button.toolTip = nil
    }

    private var clockFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func measureClockWidth() -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: clockFont]
        let widest = ClockFormat.sampleDates(calendar: .autoupdatingCurrent).map {
            (formatter.string(from: $0) as NSString).size(withAttributes: attrs).width
        }.max() ?? 0
        return widest.rounded(.up)
    }

    private func fixedLength(imageWidth: CGFloat) -> CGFloat {
        // Status bar button insets: ~5pt each side, 4pt between image and title.
        let gap: CGFloat = imageWidth > 0 ? 4 : 0
        return (10 + imageWidth + gap + clockWidth).rounded(.up)
    }

    // MARK: Geometry

    /// Where the button sits in the menu bar, for vertical centring.
    func currentPlacement() -> IconLayout.Placement {
        let thickness = NSStatusBar.system.thickness
        guard let button = item.button, let window = button.window, let screen = window.screen ?? NSScreen.main else {
            return .fullBar(thickness)
        }
        let buttonInScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        // The menu bar's height on this display: the gap above the visible frame,
        // unless the bar auto-hides, in which case trust the status bar thickness.
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        let barHeight = reserved >= 20 ? reserved : max(thickness, window.frame.height)
        // macOS 27 makes status item windows taller than the bar and lets the
        // button poke above the screen's top edge, so buttonTop can be negative.
        let buttonTop = screen.frame.maxY - buttonInScreen.maxY
        guard button.bounds.height > 0, buttonTop > -button.bounds.height / 2, buttonTop < barHeight else {
            return .fullBar(barHeight, scale: window.backingScaleFactor)
        }
        return IconLayout.Placement(barHeight: barHeight, buttonHeight: button.bounds.height,
                                    buttonTop: buttonTop, scale: window.backingScaleFactor)
    }

    private func refreshIfPlacementChanged() {
        if currentPlacement() != lastPlacement { update() }
    }

    /// Debug description of the button geometry (for `--print-geometry`).
    func geometryDescription() -> String {
        guard let button = item.button, let window = button.window else { return "no button window" }
        let p = currentPlacement()
        let screen = window.screen
        return """
        thickness=\(NSStatusBar.system.thickness) window=\(window.frame) button=\(button.frame) \
        buttonInScreen=\(window.convertToScreen(button.convert(button.bounds, to: nil))) \
        screen=\(screen?.frame ?? .zero) visible=\(screen?.visibleFrame ?? .zero) \
        placement=bar \(p.barHeight) button \(p.buttonHeight)@\(p.buttonTop) scale \(p.scale) \
        image=\(button.image?.size ?? .zero)
        """
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onClick?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            // Clear so the next left click toggles the calendar instead of the menu.
            item.menu = nil
        }
    }

    @objc private func openSettings() { onOpenSettings?() }

    /// Button frame in screen coordinates, if the item has a window.
    var screenFrame: CGRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var isVisible: Bool {
        item.button?.window?.occlusionState.contains(.visible) ?? false
    }
}
