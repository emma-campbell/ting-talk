import Foundation

/// A named binding for a common dictation tool (A3). Each assumes the tool's
/// default shortcut, or one it offers in its own settings; only Raycast is
/// verified on hardware so far (M5).
public struct TriggerPreset: Equatable, Sendable {
    public let name: String
    public let binding: TriggerBinding

    public static let all = [
        TriggerPreset(name: "Raycast", binding: .raycast),
        // Keyboard settings → Dictation → Shortcut → "Press Control Key Twice".
        TriggerPreset(name: "macOS Dictation",
                      binding: TriggerBinding(shortcut: Shortcut(keys: [.control], taps: 2), mode: .toggle)),
        TriggerPreset(name: "Superwhisper",
                      binding: TriggerBinding(shortcut: Shortcut(keys: [.option, .code(KeyCode.space)]), mode: .toggle)),
        TriggerPreset(name: "Wispr Flow",
                      binding: TriggerBinding(shortcut: Shortcut(keys: [.function]), mode: .hold)),
    ]

    /// The preset with exactly this binding, or nil for a custom one.
    public static func matching(_ binding: TriggerBinding) -> TriggerPreset? {
        all.first { $0.binding == binding }
    }
}

extension TriggerBinding {
    public static let `default` = raycast

    /// E.g. "⌘ + ⌘, toggle" or "hold fn".
    public func label(keyName: (UInt16) -> String) -> String {
        let keys = shortcut.label(keyName: keyName)
        return mode == .hold ? "hold \(keys)" : "\(keys), toggle"
    }
}

extension Shortcut {
    /// E.g. "⌃⌥A" or "⌘ + ⌘". `keyName` names regular keys by the current
    /// keyboard layout; keys with no character (Space, F5) are named here.
    public func label(keyName: (UInt16) -> String) -> String {
        let keys = self.keys.map { key in
            if case .code(let code) = key { return KeyCode.names[code] ?? keyName(code) }
            return key.symbol
        }.joined()
        return Array(repeating: keys, count: taps).joined(separator: " + ")
    }
}

extension Key {
    /// The modifiers in the order macOS writes them: ⌃⌥⇧⌘, then fn.
    public static let modifiers: [Key] = [.control, .option, .shift, .command, .function]

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        case .function: "fn"
        case .code(let code): KeyCode.names[code] ?? "key \(code)"
        }
    }
}

extension KeyCode {
    public static let delete: UInt16 = 0x33
    public static let f5: UInt16 = 0x60

    /// Keys whose name doesn't depend on the keyboard layout.
    static let names: [UInt16: String] = [
        space: "Space", returnKey: "↩", tab: "⇥", escape: "⎋", delete: "⌫",
        upArrow: "↑", downArrow: "↓", leftArrow: "←", rightArrow: "→",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}

/// Records a custom shortcut from the keys the user presses (A3). A key
/// pressed with modifiers held is a chord; modifiers pressed and released on
/// their own (fn, or ⌘ for a double-tap) are a modifier shortcut. Escape on
/// its own cancels.
public struct ShortcutRecorder: Sendable {
    public enum Result: Equatable, Sendable {
        case keys([Key])
        case cancelled
    }

    /// Modifiers held now, and the most held at once since none were.
    private var held: Set<Key> = []
    private var peak: Set<Key> = []

    public init() {}

    /// Call with every change in held modifiers. Returns a result once all
    /// are released without a regular key having been pressed.
    public mutating func modifiersChanged(_ modifiers: Set<Key>) -> Result? {
        held = modifiers
        if held.isEmpty {
            defer { peak = [] }
            return peak.isEmpty ? nil : .keys(Self.ordered(peak))
        }
        if held.isSuperset(of: peak) { peak = held }
        return nil
    }

    /// Call when a regular key goes down. Uses the modifiers the recorder has
    /// seen held, not the event's flags, since macOS flags arrows and F-keys
    /// as fn even when it isn't pressed.
    public mutating func keyDown(_ code: UInt16) -> Result {
        defer { peak = [] }
        if held.isEmpty && code == KeyCode.escape { return .cancelled }
        return .keys(Self.ordered(held) + [.code(code)])
    }

    private static func ordered(_ modifiers: Set<Key>) -> [Key] {
        Key.modifiers.filter(modifiers.contains)
    }
}
