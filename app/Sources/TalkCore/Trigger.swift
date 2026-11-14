import Foundation

/// A key the app can press: a modifier or a regular key by virtual key code.
public enum Key: Hashable, Codable, Sendable {
    case command, option, control, shift, function
    case code(UInt16)
}

/// macOS virtual key codes (kVK_*) for the regular keys we name.
public enum KeyCode {
    public static let space: UInt16 = 0x31
}

public enum KeyEvent: Equatable, Sendable {
    case down(Key)
    case up(Key)
    case pause(TimeInterval)
}

/// Keys pressed together, `taps` times (2 for double-tap shortcuts).
public struct Shortcut: Equatable, Codable, Sendable {
    public static let holdTime: TimeInterval = 0.03
    public static let tapGap: TimeInterval = 0.06

    public var keys: [Key]
    public var taps: Int

    public init(keys: [Key], taps: Int = 1) {
        self.keys = keys
        self.taps = taps
    }

    var tapEvents: [KeyEvent] {
        let one = keys.map(KeyEvent.down) + [.pause(Self.holdTime)]
            + keys.reversed().map(KeyEvent.up)
        return (0..<taps).flatMap { i in i == 0 ? one : [.pause(Self.tapGap)] + one }
    }
}

/// What "talking" drives: a shortcut, and whether it toggles or is held.
public struct TriggerBinding: Equatable, Codable, Sendable {
    public enum Mode: String, Codable, Sendable { case toggle, hold }

    public var shortcut: Shortcut
    public var mode: Mode

    public init(shortcut: Shortcut, mode: Mode) {
        self.shortcut = shortcut
        self.mode = mode
    }

    /// Verified on hardware: Raycast dictation toggles on a ⌘ double-tap.
    public static let raycast = TriggerBinding(shortcut: Shortcut(keys: [.command], taps: 2), mode: .toggle)
}

/// Turns the detector's talking state into key events for the dictation tool.
///
/// In toggle mode the tool's on/off state can't be read, so it's inferred:
/// we toggle when talking disagrees with that belief, at least `minToggleGap`
/// apart so two toggles never merge into one burst (e.g. four ⌘ taps). A
/// change inside the gap is deferred until `nextDeadline`, and if talking
/// flips back before then nothing is sent.
public struct TriggerController: Sendable {
    public private(set) var binding: TriggerBinding
    public private(set) var isActive = false

    private let minToggleGap: TimeInterval
    private var lastToggle = -TimeInterval.infinity
    private var wantsActive = false

    public init(binding: TriggerBinding, minToggleGap: TimeInterval = 0.4) {
        self.binding = binding
        self.minToggleGap = minToggleGap
    }

    /// When the caller must call `update` again to deliver a deferred toggle.
    public var nextDeadline: TimeInterval? {
        wantsActive != isActive ? lastToggle + minToggleGap : nil
    }

    public mutating func update(talking: Bool, now: TimeInterval) -> [KeyEvent] {
        wantsActive = talking
        guard talking != isActive else { return [] }
        switch binding.mode {
        case .hold:
            isActive = talking
            return talking
                ? binding.shortcut.keys.map(KeyEvent.down)
                : binding.shortcut.keys.reversed().map(KeyEvent.up)
        case .toggle:
            guard now - lastToggle >= minToggleGap else { return [] }
            isActive = talking
            lastToggle = now
            return binding.shortcut.tapEvents
        }
    }

    /// Ends dictation now (pause, input lost, quitting). In toggle mode a stop
    /// inside the gap waits out the remainder rather than being dropped.
    public mutating func stop(now: TimeInterval) -> [KeyEvent] {
        wantsActive = false
        guard isActive else { return [] }
        isActive = false
        switch binding.mode {
        case .hold:
            return binding.shortcut.keys.reversed().map(KeyEvent.up)
        case .toggle:
            let wait = lastToggle + minToggleGap - now
            lastToggle = max(now, lastToggle + minToggleGap)
            return (wait > 0 ? [.pause(wait)] : []) + binding.shortcut.tapEvents
        }
    }

    /// Switches shortcut, first stopping dictation with the old one.
    public mutating func setBinding(_ new: TriggerBinding, now: TimeInterval) -> [KeyEvent] {
        let events = stop(now: now)
        binding = new
        return events
    }
}
