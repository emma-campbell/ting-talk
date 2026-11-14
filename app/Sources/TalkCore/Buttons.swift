import Foundation

/// The Ting's tone frequencies. Must match firmware/code.py (PILOT_HZ, BUTTONS).
public enum Tones {
    public static let talk = 18_000.0
    /// Every tone, in a fixed order: talk, then the buttons top to bottom.
    public static let all = [talk] + TingButton.allCases.map(\.frequency)
}

/// The side buttons, top to bottom (D7).
public enum TingButton: String, CaseIterable, Codable, Sendable {
    case top, middle, bottom

    public var frequency: Double {
        switch self {
        case .top: 16_000
        case .middle: 17_000
        case .bottom: 19_000
        }
    }
}

extension KeyCode {
    public static let returnKey: UInt16 = 0x24
    public static let tab: UInt16 = 0x30
    public static let escape: UInt16 = 0x35
    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E
}

/// Detects several tones at once, one `PilotDetector` per frequency (A11).
/// Each compares its own bin with neighbours ±400/±800 Hz away, so tones must
/// stay clear of each other's neighbour bins (see Tones).
public struct ToneBank {
    private var detectors: [PilotDetector]

    public init(sampleRate: Double, frequencies: [Double]) {
        detectors = frequencies.map { PilotDetector(sampleRate: sampleRate, frequency: $0) }
    }

    /// Feed the next samples; returns each tone's state, in `frequencies` order.
    public mutating func process(_ samples: some Collection<Float>) -> [Bool] {
        detectors.indices.map { detectors[$0].process(samples) }
    }
}

/// Which key each button sends (nil sends nothing), whether holding it
/// repeats, and how fast (A11, A12).
public struct ButtonMapping: Equatable, Codable, Sendable {
    public static let repeatDelayChoices: [TimeInterval] = [0.25, 0.4, 0.6, 0.8]
    public static let repeatIntervalChoices: [TimeInterval] = [0.05, 0.1, 0.15, 0.2]
    /// A13: Return and Escape fire on release, only after a click shorter
    /// than this; a longer hold sends nothing.
    public static let confirmMaxHold: TimeInterval = 0.5

    private var keys: [TingButton: Key]
    private var repeating: Set<TingButton>
    /// Hold time before the first repeat.
    public var repeatDelay: TimeInterval = 0.4
    /// Time between repeats after that.
    public var repeatInterval: TimeInterval = 0.1

    /// For answering Claude Code's questions: move up, move down, confirm.
    public static let `default`: ButtonMapping = {
        var mapping = ButtonMapping(keys: [:], repeating: [])
        mapping.set(.code(KeyCode.upArrow), for: .top)
        mapping.set(.code(KeyCode.downArrow), for: .middle)
        mapping.set(.code(KeyCode.returnKey), for: .bottom)
        return mapping
    }()

    public func key(for button: TingButton) -> Key? { keys[button] }

    public func repeats(for button: TingButton) -> Bool {
        repeating.contains(button) && keys[button].map(Self.canRepeat) ?? false
    }

    /// Sets the key and resets repeat to that key's default: on for arrows,
    /// off for everything else, so a held Return can't submit repeatedly.
    public mutating func set(_ key: Key?, for button: TingButton) {
        keys[button] = key
        setRepeats(key.map(Self.repeatsByDefault) ?? false, for: button)
    }

    public mutating func setRepeats(_ on: Bool, for button: TingButton) {
        if on, let key = keys[button], Self.canRepeat(key) {
            repeating.insert(button)
        } else {
            repeating.remove(button)
        }
    }

    /// Return and Escape: sent on a short click only, never repeated (A13).
    public static func isConfirm(_ key: Key) -> Bool {
        if case .code(let code) = key { return code == KeyCode.returnKey || code == KeyCode.escape }
        return false
    }

    public static func canRepeat(_ key: Key) -> Bool { !isConfirm(key) }

    private static func repeatsByDefault(_ key: Key) -> Bool {
        let arrows = [KeyCode.upArrow, KeyCode.downArrow, KeyCode.leftArrow, KeyCode.rightArrow]
        if case .code(let code) = key { return arrows.contains(code) }
        return false
    }
}

/// Turns button states into key taps: one tap per press, then repeats while
/// held for buttons that repeat. Return and Escape instead go out on release
/// after a short click (A13). Call `update` again at `nextDeadline` to
/// deliver a repeat when no new state arrives.
public struct ButtonMapper: Sendable {
    public var mapping: ButtonMapping
    private var pressedAt: [TingButton: TimeInterval] = [:]
    private var nextRepeat: [TingButton: TimeInterval] = [:]

    public init(mapping: ButtonMapping) { self.mapping = mapping }

    /// When the earliest pending repeat is due, if any.
    public var nextDeadline: TimeInterval? { nextRepeat.values.min() }

    /// Feed the buttons whose state is known; returns taps for new presses and
    /// due repeats, in button order.
    public mutating func update(_ states: [TingButton: Bool], now: TimeInterval) -> [KeyEvent] {
        var events: [KeyEvent] = []
        for button in TingButton.allCases {
            if let down = states[button] {
                let key = mapping.key(for: button)
                let confirm = key.map(ButtonMapping.isConfirm) ?? false
                if !down {
                    // Return/Escape go out on release, and only after a short click.
                    if let since = pressedAt.removeValue(forKey: button), let key, confirm,
                       now - since < ButtonMapping.confirmMaxHold {
                        events += tap(key)
                    }
                    nextRepeat[button] = nil
                    continue
                }
                if pressedAt[button] == nil {
                    pressedAt[button] = now
                    guard let key, !confirm else { continue }
                    events += tap(key)
                    if mapping.repeats(for: button) {
                        nextRepeat[button] = now + mapping.repeatDelay
                    }
                    continue
                }
            }
            // Held: send a repeat if one is due. If we fell behind, send just
            // one and reschedule from now rather than bursting the missed ones.
            guard let due = nextRepeat[button], now >= due,
                  let key = mapping.key(for: button) else { continue }
            events += tap(key)
            let next = due + mapping.repeatInterval
            nextRepeat[button] = next > now ? next : now + mapping.repeatInterval
        }
        return events
    }

    private func tap(_ key: Key) -> [KeyEvent] {
        [.down(key), .pause(Shortcut.holdTime), .up(key)]
    }
}
