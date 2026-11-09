import CoreGraphics
import Foundation

/// Pure pieces of the Settings window: option mappings, labels and sizing.
public enum SettingsModel {
    /// The Icon picker: the two styles plus None (which is `hideIcon`).
    public enum IconChoice: String, CaseIterable, Sendable {
        case outline, filled, none

        public init(style: IconLayout.Style, hidden: Bool) {
            self = hidden ? .none : (style == .filled ? .filled : .outline)
        }

        public var title: String {
            switch self {
            case .outline: "Outline"
            case .filled: "Filled"
            case .none: "None"
            }
        }

        /// The stored style; None keeps whatever style was set before.
        public func style(keeping current: IconLayout.Style) -> IconLayout.Style {
            switch self {
            case .outline: .outline
            case .filled: .filled
            case .none: current
            }
        }

        public var hidesIcon: Bool { self == .none }
    }

    /// With no icon and no clock the item would be empty, so the status item
    /// falls back to the date icon; Settings says so.
    public static func showsEmptyItemWarning(icon: IconChoice, clockPattern: String) -> Bool {
        icon == .none && ClockFormat(clockPattern).isEmpty
    }

    /// Clock presets. Anything else is Custom.
    public enum ClockPreset: String, CaseIterable, Sendable {
        case none, time, dayTime, dayDateTime, custom

        public var pattern: String? {
            switch self {
            case .none: ""
            case .time: "h:mm a"
            case .dayTime: "EEE h:mm a"
            case .dayDateTime: "EEE d MMM h:mm a"
            case .custom: nil
            }
        }

        public static func matching(_ pattern: String) -> ClockPreset {
            let p = pattern.trimmingCharacters(in: .whitespaces)
            return allCases.first { $0.pattern == p } ?? .custom
        }

        /// Menu title: the preset's output at Mon 9 Nov, 1:00 PM.
        public func title(format: (String) -> String) -> String {
            switch self {
            case .none: "None"
            case .custom: "Custom…"
            default: format(pattern ?? "")
            }
        }

        /// A fixed sample (Monday 9 November 2026, 13:00) for preset titles.
        public static func sampleDate(calendar: Calendar) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 13, minute: 0)) ?? Date()
        }
    }

    public static func minutes(_ n: Int) -> String { "\(n) min" }
    public static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    /// Weekdays (1 = Sunday) in display order starting from `firstWeekday`.
    public static func orderedWeekdays(firstWeekday: Int) -> [Int] {
        let first = min(max(firstWeekday, 1), 7)
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// Show or hide every calendar in one account. Returns the new selection
    /// and what to store (nil = "all calendars", the default).
    public static func setAll(_ ids: [String], on: Bool, selected: Set<String>, allIDs: Set<String>)
        -> (selected: Set<String>, stored: Set<String>?) {
        var s = selected
        if on { s.formUnion(ids) } else { s.subtract(ids) }
        return (s, s == allIDs ? nil : s)
    }

    /// Whether an account's link should read "Hide all" (everything shown) or "Show all".
    public static func allShown(_ ids: [String], selected: Set<String>) -> Bool {
        !ids.isEmpty && ids.allSatisfy(selected.contains)
    }

    /// Window content height for a tab: its natural height, or the most the
    /// screen allows, in which case the tab scrolls.
    public static func contentHeight(natural: CGFloat, available: CGFloat) -> (height: CGFloat, scrolls: Bool) {
        let h = ceil(natural)
        return h <= available ? (h, false) : (max(200, floor(available)), true)
    }

    /// Theme cards and the two mode toggles, mapped onto `ThemeChoice`.
    public enum ThemeMode: Sendable, Equatable {
        case flavor(CatppuccinFlavor), matchSystem, systemColors

        public init(_ choice: ThemeChoice) {
            switch choice {
            case .system: self = .systemColors
            case .catppuccinAuto: self = .matchSystem
            case .latte: self = .flavor(.latte)
            case .frappe: self = .flavor(.frappe)
            case .macchiato: self = .flavor(.macchiato)
            case .mocha: self = .flavor(.mocha)
            }
        }

        public var choice: ThemeChoice {
            switch self {
            case .systemColors: .system
            case .matchSystem: .catppuccinAuto
            case .flavor(.latte): .latte
            case .flavor(.frappe): .frappe
            case .flavor(.macchiato): .macchiato
            case .flavor(.mocha): .mocha
            }
        }

        /// The card to ring: the chosen flavour, or the one auto is showing now.
        public func ringedFlavor(isDarkMode: Bool) -> CatppuccinFlavor? {
            switch self {
            case .flavor(let f): f
            case .matchSystem: isDarkMode ? .mocha : .latte
            case .systemColors: nil
            }
        }
    }
}
