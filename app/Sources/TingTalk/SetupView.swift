import SwiftUI
import TalkCore

/// The first-run walkthrough (A5): one permission at a time, then a live test.
struct SetupView: View {
    let setup: SetupCoordinator
    let monitor: PilotMonitor

    var body: some View {
        let state = setup.state
        VStack(alignment: .leading, spacing: 18) {
            Text("TingTalk needs two permissions, then you can check your EP-2350 is heard.")
                .foregroundStyle(.secondary)

            StepRow(
                number: 1, title: "Microphone", done: state.microphone == .allowed,
                active: state.currentStep == .microphone,
                detail: "To listen to the input your Ting's cable is plugged into and hear its tones. "
                    + "Nothing is recorded or sent anywhere."
            ) {
                if state.microphone == .denied {
                    Button("Open Microphone settings") { setup.openSettings("Privacy_Microphone") }
                    Text("Microphone access was turned off. Switch TingTalk on there.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Allow microphone") { setup.requestMicrophone() }
                }
            }

            StepRow(
                number: 2, title: "Accessibility", done: state.accessibility,
                active: state.currentStep == .accessibility,
                detail: "To press your dictation shortcut and the button keys for you. "
                    + "This step ticks off by itself once TingTalk is switched on."
            ) {
                HStack {
                    Button("Allow Accessibility…") { setup.requestAccessibility() }
                    Button("Open Accessibility settings") { setup.openSettings("Privacy_Accessibility") }
                        .buttonStyle(.link)
                }
            }

            StepRow(
                number: 3, title: "Test it (optional)",
                done: state.heardSqueeze && state.heardButton,
                active: state.currentStep == .test,
                detail: "With the cable plugged in, squeeze the handle, then press any side button."
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Squeeze heard", systemImage: state.heardSqueeze ? "checkmark.circle.fill" : "circle")
                    Label("Button heard", systemImage: state.heardButton ? "checkmark.circle.fill" : "circle")
                    if case .failed(let reason) = monitor.status {
                        Text(reason).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button(state.isComplete ? "Done" : "Finish later") { setup.closeWindow() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onChange(of: monitor.isTalking) { _, talking in
            setup.heard(talking: talking, buttonPressed: false)
        }
        .onChange(of: monitor.pressedButtons) { _, pressed in
            setup.heard(talking: false, buttonPressed: !pressed.isEmpty)
        }
    }
}

private struct StepRow<Actions: View>: View {
    let number: Int
    let title: String
    let done: Bool
    let active: Bool
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? .green : active ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if active && !done { actions }
            }
        }
        .opacity(active || done ? 1 : 0.5)
    }
}
