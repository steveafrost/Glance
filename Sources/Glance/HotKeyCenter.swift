import AppKit
import Carbon.HIToolbox
import GlanceCore

/// One global hotkey via Carbon's RegisterEventHotKey (no Accessibility permission needed).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registered: KeyCombo?

    private init() {}

    /// Register `combo` (nil clears). Returns a user-facing error message on failure.
    @discardableResult
    func register(_ combo: KeyCombo?) -> String? {
        unregister()
        guard let combo else { return nil }
        guard combo.isValidGlobalHotKey else {
            return "Add ⌘, ⌥ or ⌃ to the shortcut so it doesn’t interfere with typing."
        }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x474C_4E43) /* 'GLNC' */, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            let name = combo.displayString(characterForKeyCode: KeyboardLayout.character(for:))
            if status == eventHotKeyExistsErr {
                return "\(name) is already used by another app or by macOS. Choose a different shortcut."
            }
            return "\(name) couldn’t be registered (error \(status)). Choose a different shortcut."
        }
        hotKeyRef = ref
        registered = combo
        return nil
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registered = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            // Carbon delivers hotkey events on the main thread's run loop.
            MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

enum KeyboardLayout {
    /// The character the current keyboard layout produces for a key code, if printable.
    static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= KeyCombo.cmdKey }
        if flags.contains(.option) { m |= KeyCombo.optionKey }
        if flags.contains(.control) { m |= KeyCombo.controlKey }
        if flags.contains(.shift) { m |= KeyCombo.shiftKey }
        return m
    }
}
