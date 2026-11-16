import AppKit
import Carbon
import TalkCore

/// Names keys and bindings for display, using the current keyboard layout.
@MainActor
enum KeyNames {
    /// E.g. "Raycast (⌘ + ⌘, toggle)" or "⌃⌥D, toggle".
    static func describe(_ binding: TriggerBinding) -> String {
        let label = binding.label(keyName: name)
        return TriggerPreset.matching(binding).map { "\($0.name) (\(label))" } ?? label
    }

    /// The character a key types on the current layout, e.g. "A" for kVK_ANSI_A.
    static func name(_ code: UInt16) -> String {
        // The value of kTISPropertyUnicodeKeyLayoutData, which Swift 6 won't
        // let us read directly because it's a mutable global.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, "TISPropertyUnicodeKeyLayoutData" as CFString)
        else { return "key \(code)" }
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                           code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
                           chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "key \(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// The modifiers in an event's flags, as recorder keys.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<Key> {
        var keys: Set<Key> = []
        if flags.contains(.control) { keys.insert(.control) }
        if flags.contains(.option) { keys.insert(.option) }
        if flags.contains(.shift) { keys.insert(.shift) }
        if flags.contains(.command) { keys.insert(.command) }
        if flags.contains(.function) { keys.insert(.function) }
        return keys
    }
}
