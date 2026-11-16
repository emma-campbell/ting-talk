import SwiftUI
import TalkCore

struct SettingsView: View {
    let device: TingDevice
    let monitor: PilotMonitor
    @State private var inputs: [String] = []
    @State private var verboseLogging = Logging.verbose
    /// Shows the custom controls even when the custom binding happens to
    /// match a preset.
    @State private var isCustom = false

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
            Section("Dictation") {
                Picker("Tool", selection: toolSelection) {
                    ForEach(TriggerPreset.all, id: \.name) { Text($0.name).tag($0.name) }
                    Text("Custom").tag(Self.custom)
                }
                if isCustom || TriggerPreset.matching(monitor.binding) == nil {
                    LabeledContent("Shortcut") {
                        ShortcutField(shortcut: shortcutBinding(\.keys), taps: monitor.binding.taps)
                    }
                    Picker("Mode", selection: shortcutBinding(\.mode)) {
                        Text("Toggle").tag(TriggerBinding.Mode.toggle)
                        Text("Hold").tag(TriggerBinding.Mode.hold)
                    }
                    .pickerStyle(.segmented)
                    Picker("Press", selection: shortcutBinding(\.taps)) {
                        Text("Once").tag(1)
                        Text("Twice").tag(2)
                    }
                    .disabled(monitor.binding.mode == .hold)
                }
                Text("Set the same shortcut in your dictation tool. Toggle presses it once when "
                     + "you squeeze and again when you let go; hold keeps it down while you talk.")
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

    private static let custom = "Custom"

    private var toolSelection: Binding<String> {
        Binding(
            get: {
                isCustom ? Self.custom : TriggerPreset.matching(monitor.binding)?.name ?? Self.custom
            },
            set: { name in
                isCustom = name == Self.custom
                if let preset = TriggerPreset.all.first(where: { $0.name == name }) {
                    monitor.binding = preset.binding
                }
            })
    }

    private func shortcutBinding<Value>(_ field: WritableKeyPath<TriggerBinding, Value>) -> Binding<Value> {
        Binding(
            get: { monitor.binding[keyPath: field] },
            set: { value in
                var binding = monitor.binding
                binding[keyPath: field] = value
                monitor.binding = binding
            })
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

private extension TriggerBinding {
    var keys: [Key] {
        get { shortcut.keys }
        set { shortcut.keys = newValue }
    }

    var taps: Int {
        get { shortcut.taps }
        set { shortcut.taps = newValue }
    }
}

/// Shows a shortcut and records a new one on click (A3): press a chord, or
/// press and release modifiers on their own (e.g. fn). Escape cancels.
private struct ShortcutField: View {
    @Binding var shortcut: [Key]
    /// Only for the label; the Press picker sets it.
    let taps: Int
    @State private var monitor: Any?
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        Button(monitor == nil ? Shortcut(keys: shortcut, taps: taps).label(keyName: KeyNames.name) : "Type a shortcut…") {
            monitor == nil ? startRecording() : stopRecording()
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recorder = ShortcutRecorder()
        // Swallows keys while recording, so ⌘Q and friends don't act.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let result = event.type == .keyDown
                ? recorder.keyDown(event.keyCode)
                : recorder.modifiersChanged(KeyNames.modifiers(event.modifierFlags))
            switch result {
            case .keys(let keys): shortcut = keys; stopRecording()
            case .cancelled: stopRecording()
            case nil: break
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
