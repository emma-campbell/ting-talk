import AppKit
import SwiftUI
import TalkCore

@main
struct TingTalkApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(monitor: delegate.monitor)
        } label: {
            let monitor = delegate.monitor
            Image(systemName: monitor.isPaused ? "mic.slash" : monitor.isTalking ? "mic.fill" : "mic")
                .task { monitor.start() }
        }
        Settings {
            SettingsView(device: delegate.device, monitor: delegate.monitor)
        }
    }
}

private struct StatusMenu: View {
    @Bindable var monitor: PilotMonitor
    @State private var trusted = KeySender.isTrusted

    var body: some View {
        Text(monitor.isTalking ? "Talking" : "Idle")
        switch monitor.status {
        case .stopped: Text("Not listening")
        case .paused: Text("Paused: not listening")
        case .listening(let device): Text("Listening on \(device)")
        case .failed(let reason): Text(reason)
        }
        Text("Dictation: \(monitor.binding.label)")
        if !trusted {
            // A5: without Accessibility the key presses are silently dropped.
            Button("⚠︎ Allow Accessibility to send shortcuts…") {
                KeySender.requestTrust()
            }
        }
        Divider()
        Toggle("Pause listening", isOn: $monitor.isPaused)
        Button("Restart listening") { monitor.start() }
            .disabled(monitor.isPaused)
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .onAppear { trusted = KeySender.isTrusted }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = PilotMonitor()
    let device = TingDevice()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon (A6).
        NSApp.setActivationPolicy(.accessory)
        if !KeySender.isTrusted { KeySender.requestTrust() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave the dictation tool running after we're gone.
        monitor.shutdown()
    }
}

private extension TriggerBinding {
    var label: String {
        let keys = shortcut.keys.map(\.symbol).joined()
        let pressed = shortcut.taps == 2 ? "double-tap \(keys)" : keys
        return self == .raycast ? "Raycast (\(pressed), toggle)" : "\(pressed), \(mode.rawValue)"
    }
}

private extension Key {
    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        case .function: "fn"
        case .code(KeyCode.space): "Space"
        case .code(let code): "key \(code)"
        }
    }
}
