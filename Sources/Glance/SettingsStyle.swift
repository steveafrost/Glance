import AppKit
import GlanceCore
import SwiftUI

/// Catppuccin colours for the Settings window, resolved for the current theme.
struct SettingsPalette: Equatable {
    var mantle, base, surface0, surface1, text, subtext0, overlay0, accent, onAccent, destructive: Color
    var isDark: Bool

    @MainActor
    static func current() -> SettingsPalette {
        let appearance = ThemeColors.forcedAppearance ?? NSApp.effectiveAppearance
        var c: ThemeColors!
        appearance.performAsCurrentDrawingAppearance { c = ThemeColors.current(for: appearance) }
        func s(_ n: NSColor) -> Color { Color(nsColor: n.usingColorSpace(.sRGB) ?? n) }
        return SettingsPalette(mantle: s(c.mantle), base: s(c.background), surface0: s(c.surface0), surface1: s(c.surface1),
                               text: s(c.primaryText), subtext0: s(c.secondaryText), overlay0: s(c.otherMonthText),
                               accent: s(c.controlAccent), onAccent: s(c.onAccent), destructive: s(c.destructive),
                               isDark: c.isDark)
    }

    var nsMantle: NSColor { NSColor(mantle) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = SettingsPalette(mantle: .clear, base: .clear, surface0: .gray, surface1: .gray, text: .primary,
                                              subtext0: .secondary, overlay0: .secondary, accent: .accentColor,
                                              onAccent: .white, destructive: .red, isDark: false)
}

extension EnvironmentValues {
    var palette: SettingsPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
