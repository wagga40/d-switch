import Cocoa
import Carbon

struct Shortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_M),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    private static let keyCodeKey = "hotkeyKeyCode"
    private static let modifiersKey = "hotkeyModifiers"

    static func load() -> Shortcut {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeKey) != nil,
              defaults.object(forKey: modifiersKey) != nil else {
            return .default
        }
        let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
        let modifiers = UInt32(defaults.integer(forKey: modifiersKey))
        return Shortcut(keyCode: keyCode, carbonModifiers: modifiers)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(carbonModifiers), forKey: Self.modifiersKey)
    }

    /// Builds a Shortcut from an NSEvent. Returns nil if no modifier
    /// (cmd/shift/option/control) is held — bare-letter shortcuts would
    /// hijack regular typing.
    static func from(event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command)  { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)    { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)   { carbon |= UInt32(optionKey) }
        if flags.contains(.control)  { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil }
        return Shortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }

    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "\u{2303}" } // ⌃
        if carbonModifiers & UInt32(optionKey)  != 0 { result += "\u{2325}" } // ⌥
        if carbonModifiers & UInt32(shiftKey)   != 0 { result += "\u{21E7}" } // ⇧
        if carbonModifiers & UInt32(cmdKey)     != 0 { result += "\u{2318}" } // ⌘
        result += Self.keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        if let named = namedKeys[Int(keyCode)] { return named }
        // Try to derive a printable character via the current keyboard layout
        if let glyph = printableCharacter(for: keyCode) { return glyph }
        return "Key \(keyCode)"
    }

    private static let namedKeys: [Int: String] = [
        kVK_Return:           "\u{21A9}",   // ↩
        kVK_Tab:              "\u{21E5}",   // ⇥
        kVK_Space:            "Space",
        kVK_Delete:           "\u{232B}",   // ⌫
        kVK_Escape:           "\u{238B}",   // ⎋
        kVK_LeftArrow:        "\u{2190}",
        kVK_RightArrow:       "\u{2192}",
        kVK_DownArrow:        "\u{2193}",
        kVK_UpArrow:          "\u{2191}",
        kVK_F1:  "F1",  kVK_F2:  "F2",  kVK_F3:  "F3",  kVK_F4:  "F4",
        kVK_F5:  "F5",  kVK_F6:  "F6",  kVK_F7:  "F7",  kVK_F8:  "F8",
        kVK_F9:  "F9",  kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_Home:        "Home",
        kVK_End:          "End",
        kVK_PageUp:       "Page\u{2191}",
        kVK_PageDown:     "Page\u{2193}",
        kVK_ForwardDelete:"\u{2326}",      // ⌦
    ]

    private static func printableCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return -1
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.isEmpty ? nil : s.uppercased()
    }
}
