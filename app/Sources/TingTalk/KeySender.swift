import ApplicationServices
import Foundation
import TalkCore

/// Posts key events to macOS. Needs Accessibility permission (A5).
enum KeySender {
    private static let queue = DispatchQueue(label: "TingTalk.KeySender")

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Accessibility settings.
    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 won't let us
        // read directly because it's a mutable global.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Sends events in order on a serial queue, so pauses don't block the UI.
    /// `wait` blocks until done (used when quitting).
    static func send(_ events: [KeyEvent], wait: Bool = false) {
        guard !events.isEmpty else { return }
        let queued = ProcessInfo.processInfo.systemUptime
        let work: @Sendable () -> Void = {
            let start = ProcessInfo.processInfo.systemUptime
            post(events)
            if Logging.verbose {
                let end = ProcessInfo.processInfo.systemUptime
                log(String(format: "posted %d events: waited %.0f ms, took %.0f ms",
                           events.count, (start - queued) * 1000, (end - start) * 1000))
            }
        }
        wait ? queue.sync(execute: work) : queue.async(execute: work)
    }

    private static func post(_ events: [KeyEvent]) {
        var flags: CGEventFlags = []
        for event in events {
            switch event {
            case .pause(let seconds):
                Thread.sleep(forTimeInterval: seconds)
            case .down(let key):
                if let flag = key.flag { flags.insert(flag) }
                emit(key, down: true, flags: flags)
            case .up(let key):
                if let flag = key.flag { flags.remove(flag) }
                emit(key, down: false, flags: flags)
            }
        }
    }

    private static func emit(_ key: Key, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key.virtualKey, keyDown: down)
        else { return }
        // Modifiers arrive as flags-changed events, not key down/up.
        if key.flag != nil { event.type = .flagsChanged }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

private extension Key {
    var virtualKey: CGKeyCode {
        switch self {
        case .command: 0x37
        case .shift: 0x38
        case .option: 0x3A
        case .control: 0x3B
        case .function: 0x3F
        case .code(let code): code
        }
    }

    var flag: CGEventFlags? {
        switch self {
        case .command: .maskCommand
        case .shift: .maskShift
        case .option: .maskAlternate
        case .control: .maskControl
        case .function: .maskSecondaryFn
        case .code: nil
        }
    }
}
