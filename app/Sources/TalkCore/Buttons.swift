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

/// Which key each button sends; nil sends nothing.
public struct ButtonMapping: Equatable, Codable, Sendable {
    private var keys: [TingButton: Key]

    /// For answering Claude Code's questions: move up, move down, confirm.
    public static let `default` = ButtonMapping(keys: [
        .top: .code(KeyCode.upArrow),
        .middle: .code(KeyCode.downArrow),
        .bottom: .code(KeyCode.returnKey),
    ])

    public func key(for button: TingButton) -> Key? { keys[button] }

    public mutating func set(_ key: Key?, for button: TingButton) { keys[button] = key }
}

/// Turns button states into key taps: one tap per press, no repeat while held.
public struct ButtonMapper: Sendable {
    public var mapping: ButtonMapping
    private var pressed: Set<TingButton> = []

    public init(mapping: ButtonMapping) { self.mapping = mapping }

    /// Feed the buttons whose state is known; returns taps for new presses,
    /// in button order.
    public mutating func update(_ states: [TingButton: Bool]) -> [KeyEvent] {
        var events: [KeyEvent] = []
        for button in TingButton.allCases {
            guard let down = states[button] else { continue }
            let wasDown = pressed.contains(button)
            if down { pressed.insert(button) } else { pressed.remove(button) }
            if down, !wasDown, let key = mapping.key(for: button) {
                events += [.down(key), .pause(Shortcut.holdTime), .up(key)]
            }
        }
        return events
    }
}
