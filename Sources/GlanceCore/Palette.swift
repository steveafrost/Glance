import Foundation

/// Catppuccin flavours. Values from https://catppuccin.com/palette
/// (Latte and Mocha match the itsycal-catppuccin fork's Themer.m).
public enum CatppuccinFlavor: String, CaseIterable, Sendable, Codable {
    case latte, frappe, macchiato, mocha

    public var displayName: String {
        switch self {
        case .latte: "Latte"
        case .frappe: "Frappé"
        case .macchiato: "Macchiato"
        case .mocha: "Mocha"
        }
    }

    public var isDark: Bool { self != .latte }

    public struct Colors: Sendable, Equatable {
        public let text, subtext1, subtext0, overlay2, overlay1, overlay0: UInt32
        public let surface2, surface1, surface0, base, mantle, crust: UInt32
        public let lavender, mauve, blue, red, green, peach, yellow, teal: UInt32
    }

    public var colors: Colors {
        switch self {
        case .latte:
            Colors(text: 0x4C4F69, subtext1: 0x5C5F77, subtext0: 0x6C6F85, overlay2: 0x7C7F93,
                   overlay1: 0x8C8FA1, overlay0: 0x9CA0B0, surface2: 0xACB0BE, surface1: 0xBCC0CC,
                   surface0: 0xCCD0DA, base: 0xEFF1F5, mantle: 0xE6E9EF, crust: 0xDCE0E8,
                   lavender: 0x7287FD, mauve: 0x8839EF, blue: 0x1E66F5, red: 0xD20F39,
                   green: 0x40A02B, peach: 0xFE640B, yellow: 0xDF8E1D, teal: 0x179299)
        case .frappe:
            Colors(text: 0xC6D0F5, subtext1: 0xB5BFE2, subtext0: 0xA5ADCE, overlay2: 0x949CBB,
                   overlay1: 0x838BA7, overlay0: 0x737994, surface2: 0x626880, surface1: 0x51576D,
                   surface0: 0x414559, base: 0x303446, mantle: 0x292C3C, crust: 0x232634,
                   lavender: 0xBABBF1, mauve: 0xCA9EE6, blue: 0x8CAAEE, red: 0xE78284,
                   green: 0xA6D189, peach: 0xEF9F76, yellow: 0xE5C890, teal: 0x81C8BE)
        case .macchiato:
            Colors(text: 0xCAD3F5, subtext1: 0xB8C0E0, subtext0: 0xA5ADCB, overlay2: 0x939AB7,
                   overlay1: 0x8087A2, overlay0: 0x6E738D, surface2: 0x5B6078, surface1: 0x494D64,
                   surface0: 0x363A4F, base: 0x24273A, mantle: 0x1E2030, crust: 0x181926,
                   lavender: 0xB7BDF8, mauve: 0xC6A0F6, blue: 0x8AADF4, red: 0xED8796,
                   green: 0xA6DA95, peach: 0xF5A97F, yellow: 0xEED49F, teal: 0x8BD5CA)
        case .mocha:
            Colors(text: 0xCDD6F4, subtext1: 0xBAC2DE, subtext0: 0xA6ADC8, overlay2: 0x9399B2,
                   overlay1: 0x7F849C, overlay0: 0x6C7086, surface2: 0x585B70, surface1: 0x45475A,
                   surface0: 0x313244, base: 0x1E1E2E, mantle: 0x181825, crust: 0x11111B,
                   lavender: 0xB4BEFE, mauve: 0xCBA6F7, blue: 0x89B4FA, red: 0xF38BA8,
                   green: 0xA6E3A1, peach: 0xFAB387, yellow: 0xF9E2AF, teal: 0x94E2D5)
        }
    }

    /// The fork's role mapping (Themer.m), shared by every flavour.
    public var roles: ThemeRoles {
        let c = colors
        return ThemeRoles(
            background: c.base, highlightedWeekdayBackground: c.mantle, divider: c.surface0,
            primaryText: c.text, secondaryText: c.subtext0, otherMonthText: c.overlay0,
            weekNumberText: c.overlay1, hover: c.overlay0, selection: c.lavender, today: c.mauve,
            accent: c.blue, destructive: c.red, meeting: c.green)
    }
}

/// Colour roles the UI draws with, as sRGB hex.
public struct ThemeRoles: Sendable, Equatable {
    public let background, highlightedWeekdayBackground, divider: UInt32
    public let primaryText, secondaryText, otherMonthText, weekNumberText: UInt32
    public let hover, selection, today, accent, destructive, meeting: UInt32
}

public enum ThemeChoice: String, CaseIterable, Sendable, Codable {
    /// Native system colours, following light/dark mode.
    case system
    /// Latte in light mode, Mocha in dark mode.
    case catppuccinAuto
    case latte, frappe, macchiato, mocha

    public var displayName: String {
        switch self {
        case .system: "System (Light/Dark)"
        case .catppuccinAuto: "Catppuccin (Latte/Mocha)"
        case .latte, .frappe, .macchiato, .mocha: "Catppuccin " + (flavor(isDarkMode: false)?.displayName ?? "")
        }
    }

    /// Fixed appearance the theme forces, or nil to follow the system.
    public var forcedDark: Bool? {
        switch self {
        case .system, .catppuccinAuto: nil
        case .latte: false
        case .frappe, .macchiato, .mocha: true
        }
    }

    /// The Catppuccin flavour to draw with, or nil for system colours.
    public func flavor(isDarkMode: Bool) -> CatppuccinFlavor? {
        switch self {
        case .system: nil
        case .catppuccinAuto: isDarkMode ? .mocha : .latte
        case .latte: .latte
        case .frappe: .frappe
        case .macchiato: .macchiato
        case .mocha: .mocha
        }
    }
}
