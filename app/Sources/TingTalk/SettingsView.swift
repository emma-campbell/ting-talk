import SwiftUI
import TalkCore

struct SettingsView: View {
    let device: TingDevice
    let monitor: PilotMonitor
    @State private var inputs: [String] = []
    @State private var verboseLogging = Logging.verbose

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
                    Toggle("Repeat while held", isOn: repeatBinding(for: button))
                        .disabled(!(monitor.buttonMapping.key(for: button).map(ButtonMapping.canRepeat) ?? false))
                        .padding(.leading)
                }
                Picker("Repeat delay", selection: timingBinding(\.repeatDelay)) {
                    ForEach(ButtonMapping.repeatDelayChoices, id: \.self) { Text(seconds($0)).tag($0) }
                }
                Picker("Repeat rate", selection: timingBinding(\.repeatInterval)) {
                    ForEach(ButtonMapping.repeatIntervalChoices, id: \.self) {
                        Text("every \(seconds($0))").tag($0)
                    }
                }
                Text("Keys go to whichever app is in front. Arrows repeat by default. "
                     + "Return and Escape are sent only on a quick click, when you let go; "
                     + "holding them sends nothing, so they never submit or cancel by accident.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Toggle("Verbose logging", isOn: $verboseLogging)
                    .onChange(of: verboseLogging) { Logging.verbose = verboseLogging }
                HStack {
                    Text("Writes audio and key timing to ~/Library/Logs/TingTalk.log, "
                         + "four lines a second. Leave it off unless you're chasing a problem.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([Logging.file]) }
                        .disabled(!FileManager.default.fileExists(atPath: Logging.file.path))
                }
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

    private func repeatBinding(for button: TingButton) -> Binding<Bool> {
        Binding(
            get: { monitor.buttonMapping.repeats(for: button) },
            set: { on in
                var mapping = monitor.buttonMapping
                mapping.setRepeats(on, for: button)
                monitor.buttonMapping = mapping
            })
    }

    private func timingBinding(_ field: WritableKeyPath<ButtonMapping, TimeInterval>) -> Binding<TimeInterval> {
        Binding(
            get: { monitor.buttonMapping[keyPath: field] },
            set: { value in
                var mapping = monitor.buttonMapping
                mapping[keyPath: field] = value
                monitor.buttonMapping = mapping
            })
    }

    private func seconds(_ value: TimeInterval) -> String {
        value.formatted(.number.precision(.fractionLength(2...2))) + " s"
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
