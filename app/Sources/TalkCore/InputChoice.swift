/// Which audio input to listen on (A10).
///
/// The pilot only arrives on the input the coiled cable is plugged into, so a
/// missing choice is never swapped for another device: listening on the wrong
/// one would look like the Ting had stopped working.
public struct InputChoice: Equatable, Sendable {
    public static let defaultFragment = "CalDigit"

    public struct Item: Equatable, Sendable {
        public let name: String
        public let connected: Bool
        public var title: String { connected ? name : "\(name) (not connected)" }
    }

    /// The device name the user picked, or nil if they never did.
    public var saved: String?

    public init(saved: String?) { self.saved = saved }

    /// The input to listen on now, or nil to wait.
    public func device(in available: [String]) -> String? {
        if let saved { return available.contains(saved) ? saved : nil }
        return available.first { $0.localizedCaseInsensitiveContains(Self.defaultFragment) }
    }

    /// Picker contents: every available input, plus the saved one if it's
    /// missing, and the name to show as selected.
    public func menu(available: [String]) -> (items: [Item], selected: String?) {
        var items = available.map { Item(name: $0, connected: true) }
        if let saved, !available.contains(saved) {
            items.append(Item(name: saved, connected: false))
        }
        return (items, saved ?? device(in: available))
    }
}
