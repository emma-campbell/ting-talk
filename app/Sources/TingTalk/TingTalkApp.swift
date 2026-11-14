import AppKit
import SwiftUI
import TalkCore

@main
struct TingTalkApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(monitor: delegate.monitor, setup: delegate.setup)
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
    let setup: SetupCoordinator

    var body: some View {
        Text(monitor.isTalking ? "Talking" : "Idle")
        switch monitor.status {
        case .stopped: Text("Not listening")
        case .needsMicrophone: Text("Waiting for microphone permission")
        case .paused: Text("Paused: not listening")
        case .listening(let device): Text("Listening on \(device)")
        case .failed(let reason): Text(reason)
        }
        Text("Dictation: \(monitor.binding.label)")
        if !setup.state.isComplete {
            // A5: without both permissions nothing works; say so plainly.
            Button("⚠︎ Finish setup…") { setup.showWindow() }
        }
        Divider()
        Toggle("Pause listening", isOn: $monitor.isPaused)
        Button("Restart listening") { monitor.start() }
            .disabled(monitor.isPaused)
        Button("Setup…") { setup.showWindow() }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = PilotMonitor()
    let device = TingDevice()
    lazy var setup = SetupCoordinator(monitor: monitor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon (A6).
        NSApp.setActivationPolicy(.accessory)
        // A5: no permission prompts at launch; the walkthrough asks one at a time.
        if setup.state.needsWindow { setup.showWindow() }
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
