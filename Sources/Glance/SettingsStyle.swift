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

// MARK: Layout

/// A titled group: an overlay0 header over a rounded card.
struct SettingsSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.overlay0).padding(.leading, 12)
            }
            SettingsCard { content }
        }
    }
}

/// A base card with a 1px surface0 border and hairlines between its rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Rectangle().fill(p.surface0).frame(height: 1).padding(.leading, 12) }
                    row
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.base))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.surface0, lineWidth: 1))
    }
}

/// Label (and optional caption) on the left, control right-aligned on the same line.
struct SettingsRow<Control: View>: View {
    var label: String
    var caption: String?
    var disabled = false
    @ViewBuilder var control: Control
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13)).foregroundStyle(p.text)
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundStyle(p.subtext0)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

/// A full-width note inside a card (warnings, explanations).
struct SettingsNote: View {
    var text: String
    var symbol = "exclamationmark.triangle.fill"
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(p.accent)
            Text(text).font(.system(size: 12)).foregroundStyle(p.subtext0).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: Controls

/// An accent-tinted switch drawn from the palette.
struct ThemedSwitchStyle: ToggleStyle {
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? p.accent : p.surface1)
                // A light knob in every flavour, like the native switch.
                Circle().fill(p.isDark ? p.text : p.base)
                    .padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
            .frame(width: 34, height: 20)
            .animation(.easeOut(duration: 0.12), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Toggle"))
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
    }
}

struct ThemedSwitch: View {
    @Binding var isOn: Bool
    var body: some View { Toggle("", isOn: $isOn).labelsHidden().toggleStyle(ThemedSwitchStyle()) }
}

/// A themed pop-up menu: surface0 field, the current choice and a chevron;
/// the menu marks the selection.
struct ThemedMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    var width: CGFloat? = nil
    @Environment(\.palette) private var p

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .font(.system(size: 13)).foregroundStyle(p.text).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(p.accent)
            }
            .padding(.horizontal, 9)
            .frame(width: width, height: 24)
            .fixedSize(horizontal: width == nil, vertical: false)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.surface0))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.surface1, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// − value + in one control, the value spelled out ("5 min").
struct ThemedStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var format: (Int) -> String
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 0) {
            step("minus", by: -1)
            Rectangle().fill(p.surface1).frame(width: 1, height: 14)
            Text(format(value)).font(.system(size: 13).monospacedDigit()).foregroundStyle(p.text)
                .frame(minWidth: 64).padding(.horizontal, 4)
            Rectangle().fill(p.surface1).frame(width: 1, height: 14)
            step("plus", by: 1)
        }
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.surface0))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.surface1, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(format(value)))
        .accessibilityAdjustableAction { dir in
            value = min(max(value + (dir == .increment ? 1 : -1), range.lowerBound), range.upperBound)
        }
    }

    private func step(_ symbol: String, by delta: Int) -> some View {
        let next = value + delta
        let ok = range.contains(next)
        return Button { if ok { value = next } } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(ok ? p.accent : p.overlay0)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ok)
    }
}

/// A surface0 text field with a 1px surface1 border and an accent ring while focused.
struct ThemedTextField: View {
    var placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var monospaced = false
    @FocusState private var focused: Bool
    @Environment(\.palette) private var p

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(p.overlay0))
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
            .foregroundStyle(p.text)
            .focused($focused)
            .padding(.horizontal, 8)
            .frame(width: width, height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.surface0))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(focused ? p.accent : p.surface1, lineWidth: focused ? 2 : 1))
    }
}

/// An accent text button ("Show all").
struct AccentLink: View {
    var title: String
    var action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) { Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(p.accent) }
            .buttonStyle(.plain)
    }
}

/// A filled accent button.
struct AccentButton: View {
    var title: String
    var action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.onAccent)
                .padding(.horizontal, 12).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.accent))
        }
        .buttonStyle(.plain)
    }
}
