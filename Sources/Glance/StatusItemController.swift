import AppKit
import GlanceCore

/// The menu bar item: date icon and optional clock text.
///
/// The icon is deliberately constant: it shows the day number and nothing else.
/// No meeting camera and no update badge are drawn into it, so its pixels never
/// change while the app runs. Those signals live elsewhere (the agenda's Join
/// button, the menu item title, the accessibility label).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    let item: NSStatusItem
    var onClick: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let prefs = Preferences.shared
    private let formatter = DateFormatter()
    private(set) var clock = ClockFormat("")
    /// The widest clock string over the year (so the item's width never changes).
    private var widestClock = ""
    private var lengthCache: (key: String, length: CGFloat)?
    private var iconCache: (key: String, image: NSImage, box: CGRect?)?
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
        widestClock = clock.isEmpty ? "" : findWidestClock()
        lengthCache = nil
        update()
    }

    /// Redraw the icon and clock text for "now".
    func update(now: Date = Date()) {
        guard let button = item.button else { return }
        let day = Calendar.autoupdatingCurrent.component(.day, from: now)
        let iconText: String? = prefs.hideIcon ? nil : String(day)
        let placement = currentPlacement()
        lastPlacement = placement

        let image = iconText.map { icon(text: $0, placement: placement) }
        if button.image !== image { button.image = image }

        var title = ""
        if !clock.isEmpty {
            title = formatter.string(from: now)
            // A space separates the clock from the icon.
            let prefix = button.image == nil ? "" : " "
            button.imagePosition = button.image == nil ? .noImage : .imageLeading
            button.imageHugsTitle = true
            // A fixed length keeps the item (and everything to its left) from jittering.
            item.length = fixedLength(for: button, title: prefix + widestClock)
            button.attributedTitle = NSAttributedString(string: prefix + title, attributes: [.font: clockFont])
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            item.length = NSStatusItem.variableLength
            if button.image == nil {
                // Nothing to show: keep a minimal glyph so the item stays clickable.
                button.image = icon(text: String(day), placement: placement)
            }
        }

        var label = "Glance"
        if let iconText { label += ", \(iconText)" }
        if !title.isEmpty { label += ", \(title)" }
        button.setAccessibilityLabel(label)
        button.toolTip = nil
    }

    /// The icon only changes with the day, style or placement, so clock ticks
    /// reuse the same image.
    private func icon(text: String, placement: IconLayout.Placement) -> NSImage {
        let key = "\(text)|\(prefs.iconStyle)|\(placement)|\(prefs.iconOpticalOffset)"
        if let c = iconCache, c.key == key { return c.image }
        let (image, layout) = IconRenderer.render(text: text, style: prefs.iconStyle,
                                                  placement: placement,
                                                  opticalOffset: prefs.iconOpticalOffset)
        iconCache = (key, image, layout.boxRect)
        return image
    }

    private var clockFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func findWidestClock() -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: clockFont]
        return ClockFormat.sampleDates(calendar: .autoupdatingCurrent)
            .map { formatter.string(from: $0) }
            .max { ($0 as NSString).size(withAttributes: attrs).width < ($1 as NSString).size(withAttributes: attrs).width } ?? ""
    }

    /// The button's fitting width with the widest title, measured once per icon/format.
    private func fixedLength(for button: NSStatusBarButton, title widest: String) -> CGFloat {
        let key = "\(widest)|\(button.image?.size.width ?? 0)"
        if let c = lengthCache, c.key == key { return c.length }
        button.attributedTitle = NSAttributedString(string: widest, attributes: [.font: clockFont])
        let length = button.fittingSize.width.rounded(.up)
        lengthCache = (key, length)
        return length
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
        menu.addItem(Updater.shared.menuItem())
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

    /// Screen x of the drawn date box's centre (where the calendar's arrow
    /// points). Falls back to the button's centre with no box.
    var arrowTargetX: CGFloat? {
        guard let button = item.button, let window = button.window else { return nil }
        var x = button.bounds.midX
        if let image = button.image, let cache = iconCache, cache.image === image, let box = cache.box,
           let cell = button.cell {
            let imageRect = cell.imageRect(forBounds: button.bounds)
            // The image is drawn unscaled; box.midX is in image coordinates.
            x = imageRect.minX + box.midX * (imageRect.width / max(image.size.width, 1))
        }
        let p = button.convert(CGPoint(x: x, y: 0), to: nil)
        return window.convertPoint(toScreen: p).x
    }

    var isVisible: Bool {
        item.button?.window?.occlusionState.contains(.visible) ?? false
    }
}
