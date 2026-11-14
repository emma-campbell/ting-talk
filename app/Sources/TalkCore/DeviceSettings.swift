import Foundation

/// The Ting's settings as stored in CIRCUITPY/settings.toml (A9, D6).
///
/// Only `TING_SLEEP_AFTER` is ours. Updates rewrite that one line and leave
/// every other line, comments included, as they were.
public struct DeviceSettings: Equatable, Sendable {
    public static let sleepKey = "TING_SLEEP_AFTER"
    /// Must match the firmware's default in firmware/code.py.
    public static let defaultSleepAfter = 600
    /// Seconds; 0 means never.
    public static let sleepChoices = [300, 600, 1200, 1800, 0]

    public var sleepAfter: Int

    public static func parse(_ toml: String) -> DeviceSettings {
        let value = toml.split(whereSeparator: \.isNewline).lazy
            .compactMap(sleepValue).first
        return DeviceSettings(sleepAfter: value.flatMap { Int($0) } ?? defaultSleepAfter)
    }

    public static func updating(_ toml: String, sleepAfter: Int) -> String {
        var lines = toml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        let line = "\(sleepKey) = \(sleepAfter)"
        var replaced = false
        lines = lines.compactMap { existing in
            guard sleepValue(existing) != nil else { return existing }
            defer { replaced = true }
            return replaced ? nil : line  // first one replaced, duplicates dropped
        }
        if !replaced { lines.append(line) }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func label(forSleepAfter seconds: Int) -> String {
        switch seconds {
        case 0: "Never"
        case let s where s % 60 == 0: "\(s / 60) min"
        default: "\(seconds) s"
        }
    }

    /// Whether a CIRCUITPY drive's boot_out.txt comes from an EP-2350.
    public static func isTing(bootOut: String) -> Bool {
        bootOut.contains("Board ID:teenage_engineering_ep2350")
    }

    /// The raw value if `line` assigns our key, else nil.
    private static func sleepValue(_ line: some StringProtocol) -> Substring? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespaces) == sleepKey
        else { return nil }
        return Substring(parts[1].trimmingCharacters(in: .whitespaces))
    }
}
