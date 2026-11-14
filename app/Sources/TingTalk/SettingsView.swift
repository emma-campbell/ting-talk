import SwiftUI
import TalkCore

struct SettingsView: View {
    let device: TingDevice
    let monitor: PilotMonitor
    @State private var inputs: [String] = []

    var body: some View {
        Form {
            Section("Audio input") {
                let menu = monitor.inputChoice.menu(available: inputs)
                Picker("Listen on", selection: inputSelection(menu.selected)) {
                    ForEach(menu.items, id: \.name) { item in
                        Text(item.title).tag(Optional(item.name))
                    }
                    if menu.selected == nil {
                        Text("Choose an input").tag(String?.none)
                    }
                }
                Text("The input the Ting's coiled cable is plugged into. Set the same input "
                     + "as the microphone in your dictation tool.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Buttons") {
                ForEach(TingButton.allCases, id: \.self) { button in
                    Picker(button.label, selection: keyBinding(for: button)) {
                        ForEach(Self.keyChoices, id: \.title) { choice in
                            Text(choice.title).tag(choice.key)
                        }
                    }
                }
                Text("One key press per click, sent to whichever app is in front.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Ting") {
                Picker("Power off after", selection: sleepAfter) {
                    ForEach(choices, id: \.self) { seconds in
                        Text(DeviceSettings.label(forSleepAfter: seconds)).tag(seconds)
                    }
                }
                .disabled(current == nil)

                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = device.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            device.refresh()
            // Menu-bar apps don't come forward on their own.
            NSApp.activate()
        }
        .task {
            // Keep the list current while the window is open (plugging in an adapter).
            while !Task.isCancelled {
                inputs = AudioDevices.inputs().map(\.name)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private static let keyChoices: [(title: String, key: Key?)] = [
        ("Nothing", nil),
        ("↑ Up arrow", .code(KeyCode.upArrow)),
        ("↓ Down arrow", .code(KeyCode.downArrow)),
        ("← Left arrow", .code(KeyCode.leftArrow)),
        ("→ Right arrow", .code(KeyCode.rightArrow)),
        ("↩ Return", .code(KeyCode.returnKey)),
        ("⎋ Escape", .code(KeyCode.escape)),
        ("⇥ Tab", .code(KeyCode.tab)),
        ("Space", .code(KeyCode.space)),
    ]

    private func keyBinding(for button: TingButton) -> Binding<Key?> {
        Binding(
            get: { monitor.buttonMapping.key(for: button) },
            set: { key in
                var mapping = monitor.buttonMapping
                mapping.set(key, for: button)
                monitor.buttonMapping = mapping
            })
    }

    private func inputSelection(_ selected: String?) -> Binding<String?> {
        Binding(get: { selected }, set: { if let name = $0 { monitor.setInput(name) } })
    }

    private var current: Int? {
        if case .connected(let settings) = device.state { settings.sleepAfter } else { nil }
    }

    /// The fixed choices, plus the device's value if it's something else
    /// (e.g. 30 s set by hand for testing), so the picker can show it.
    private var choices: [Int] {
        guard let current, !DeviceSettings.sleepChoices.contains(current) else {
            return DeviceSettings.sleepChoices
        }
        return [current] + DeviceSettings.sleepChoices
    }

    private var sleepAfter: Binding<Int> {
        Binding(
            get: { current ?? DeviceSettings.defaultSleepAfter },
            set: { device.setSleepAfter($0) })
    }

    private var status: String {
        switch device.state {
        case .disconnected:
            "Connect the Ting with USB-C to change this. The coiled cable only carries "
                + "sound to the Mac. Applies on batteries only."
        case .readOnly:
            "The Ting's drive is read-only. This happens when USB is plugged in while it's "
                + "running on battery. Press the small button above the USB-C port to restart "
                + "it (squeeze the handle if it stays dark)."
        case .connected:
            "Applies on batteries only. While plugged into a computer the Ting stays on."
        }
    }
}

private extension TingButton {
    var label: String {
        switch self {
        case .top: "Top (orange)"
        case .middle: "Middle (white)"
        case .bottom: "Bottom (gray)"
        }
    }
}
