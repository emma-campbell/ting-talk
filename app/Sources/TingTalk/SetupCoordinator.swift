import AVFoundation
import AppKit
import Observation
import SwiftUI
import TalkCore

/// Drives the first-run walkthrough (A5): reads both permissions about once a
/// second so the window updates on its own when the user flips a switch in
/// System Settings, and starts listening as soon as the microphone is allowed.
@MainActor @Observable
final class SetupCoordinator {
    private(set) var state = SetupState(microphone: SetupCoordinator.microphone(), accessibility: KeySender.isTrusted)

    private let monitor: PilotMonitor
    private var window: NSWindow?

    init(monitor: PilotMonitor) {
        self.monitor = monitor
        Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refresh() {
        let wasListening = state.canListen
        state.microphone = Self.microphone()
        state.accessibility = KeySender.isTrusted
        if state.canListen, !wasListening { monitor.start() }
    }

    func heard(talking: Bool, buttonPressed: Bool) {
        state.heard(talking: talking, buttonPressed: buttonPressed)
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Adds TingTalk to the Accessibility list and shows the system prompt,
    /// alone now, so it can't race the microphone prompt.
    func requestAccessibility() { KeySender.requestTrust() }

    func openSettings(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero, styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = "Set up TingTalk"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SetupView(setup: self, monitor: monitor))
            window.center()
            self.window = window
        }
        // A menu-bar app launched while you're in another app isn't allowed to
        // take focus, so a plain makeKeyAndOrderFront leaves the window hidden
        // behind everything. orderFrontRegardless shows it anyway.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func closeWindow() { window?.close() }

    private static func microphone() -> SetupState.Microphone {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }
}
