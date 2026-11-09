import Foundation

/// A global hotkey: a virtual key code plus Carbon modifier flags.
public struct KeyCombo: Hashable, Sendable, Codable {
    // Carbon modifier bits (Events.h).
    public static let cmdKey: UInt32 = 1 << 8
    public static let shiftKey: UInt32 = 1 << 9
    public static let optionKey: UInt32 = 1 << 11
    public static let controlKey: UInt32 = 1 << 12

    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & (Self.cmdKey | Self.shiftKey | Self.optionKey | Self.controlKey)
    }

    /// A global hotkey needs a modifier other than Shift, unless it is a
    /// function key (F1–F20), so it doesn't steal ordinary typing.
    public var isValidGlobalHotKey: Bool {
        let nonShift = carbonModifiers & ~Self.shiftKey
        return nonShift != 0 || Self.functionKeyNames[keyCode] != nil
    }

    /// Modifier symbols in the macOS order ⌃⌥⇧⌘.
    public var modifierSymbols: String {
        var s = ""
        if carbonModifiers & Self.controlKey != 0 { s += "⌃" }
        if carbonModifiers & Self.optionKey != 0 { s += "⌥" }
        if carbonModifiers & Self.shiftKey != 0 { s += "⇧" }
        if carbonModifiers & Self.cmdKey != 0 { s += "⌘" }
        return s
    }

    /// Display string, e.g. "⌥⌘C". `characterForKeyCode` maps a printable
    /// key to the current keyboard layout's character.
    public func displayString(characterForKeyCode: (UInt32) -> String?) -> String {
        let key = Self.specialKeyNames[keyCode] ?? Self.functionKeyNames[keyCode]
            ?? characterForKeyCode(keyCode)?.uppercased() ?? "#\(keyCode)"
        return modifierSymbols + key
    }

    public static let functionKeyNames: [UInt32: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
        0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14",
        0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]

    public static let specialKeyNames: [UInt32: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x4C: "⌤",
    ]
}
