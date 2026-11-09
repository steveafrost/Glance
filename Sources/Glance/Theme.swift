import AppKit
import GlanceCore

/// Colours for the current theme, resolved for a given appearance.
struct ThemeColors {
    let background, highlightedWeekdayBackground, divider: NSColor
    let primaryText, secondaryText, otherMonthText, weekNumberText: NSColor
    let hover, selection, today, accent, destructive, meeting: NSColor
    /// Text drawn on top of `today`.
    let onToday: NSColor

    @MainActor
    static func current(for appearance: NSAppearance) -> ThemeColors {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if let flavor = Preferences.shared.theme.flavor(isDarkMode: isDark) {
            let r = flavor.roles
            func c(_ hex: UInt32) -> NSColor { NSColor(rgba: RGBA(hex: hex)) }
            return ThemeColors(
                background: c(r.background), highlightedWeekdayBackground: c(r.highlightedWeekdayBackground),
                divider: c(r.divider), primaryText: c(r.primaryText), secondaryText: c(r.secondaryText),
                otherMonthText: c(r.otherMonthText), weekNumberText: c(r.weekNumberText),
                hover: c(r.hover).withAlphaComponent(0.35), selection: c(r.selection), today: c(r.today),
                accent: c(r.accent), destructive: c(r.destructive), meeting: c(r.meeting),
                onToday: c(r.background))
        }
        return ThemeColors(
            background: isDark ? NSColor(white: 0.137, alpha: 1) : .windowBackgroundColor,
            highlightedWeekdayBackground: .secondarySystemFill, divider: .separatorColor,
            primaryText: .labelColor, secondaryText: .secondaryLabelColor,
            otherMonthText: .tertiaryLabelColor, weekNumberText: .secondaryLabelColor,
            hover: .quaternaryLabelColor, selection: isDark ? .secondaryLabelColor : .labelColor,
            today: .controlAccentColor, accent: .controlAccentColor, destructive: .systemRed,
            meeting: .systemGreen, onToday: .white)
    }

    /// The appearance a window should use for the current theme (nil = follow the system).
    @MainActor
    static var forcedAppearance: NSAppearance? {
        switch Preferences.shared.theme.forcedDark {
        case .some(true): NSAppearance(named: .darkAqua)
        case .some(false): NSAppearance(named: .aqua)
        case .none: nil
        }
    }
}

extension NSColor {
    convenience init(rgba c: RGBA) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    var rgba: RGBA {
        let c = usingColorSpace(.sRGB) ?? self
        return RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent),
                    a: Double(c.alphaComponent))
    }
}

/// Run `body` with `appearance` as the drawing appearance so dynamic system colours resolve correctly.
@MainActor
func withAppearance(_ appearance: NSAppearance, _ body: () -> Void) {
    appearance.performAsCurrentDrawingAppearance(body)
}
