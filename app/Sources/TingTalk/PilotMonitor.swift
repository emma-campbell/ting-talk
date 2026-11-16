import AVFoundation
import AudioToolbox
import Observation
import TalkCore

/// Listens to an input device for the Ting's tones: the talk pilot drives the
/// dictation trigger, and each button tone sends its mapped key (A11).
@MainActor @Observable
final class PilotMonitor {
    enum Status: Equatable {
        case stopped
        case needsMicrophone
        case paused
        case listening(device: String)
        case failed(String)
    }

    /// A8. Persisted; while paused nothing is captured, so macOS drops its
    /// mic-in-use indicator.
    var isPaused = UserDefaults.standard.bool(forKey: "paused") {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "paused")
            isPaused ? pause() : start()
        }
    }

    private(set) var status = Status.stopped
    /// Buttons currently held, for the walkthrough's live test.
    private(set) var pressedButtons: Set<TingButton> = []
    private(set) var isTalking = false {
        didSet { if isTalking != oldValue { drive() } }
    }

    private var engine: AVAudioEngine?
    private var controller = TriggerController(binding: UserDefaults.standard.data(forKey: "triggerBinding")
        .flatMap { try? JSONDecoder().decode(TriggerBinding.self, from: $0) } ?? .default)
    private var deadline: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    /// A3. Persisted as JSON. Changing it first stops any dictation in
    /// progress with the old shortcut.
    var binding: TriggerBinding {
        get { controller.binding }
        set {
            guard newValue != controller.binding else { return }
            deadline?.cancel()
            let events = controller.setBinding(newValue, now: now)
            log("binding=\(newValue) send=\(events)")
            KeySender.send(events)
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "triggerBinding")
        }
    }

    /// A11. Persisted as JSON; the default suits Claude Code's questions.
    var buttonMapping: ButtonMapping {
        get { buttons.mapping }
        set {
            buttons.mapping = newValue
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "buttonMapping")
        }
    }
    private var buttons = ButtonMapper(mapping: UserDefaults.standard.data(forKey: "buttonMapping")
        .flatMap { try? JSONDecoder().decode(ButtonMapping.self, from: $0) } ?? .default)

    private var repeatTimer: Task<Void, Never>?

    /// Called with every tone's state, in `Tones.all` order, when any changes.
    private func tonesChanged(_ states: [Bool]) {
        isTalking = states[0]
        pressedButtons = Set(zip(TingButton.allCases, states.dropFirst()).filter(\.1).map(\.0))
        driveButtons(Dictionary(uniqueKeysWithValues: zip(TingButton.allCases, states.dropFirst())))
    }

    /// Sends taps for new presses and due repeats, then comes back at the
    /// mapper's next deadline so repeats continue while a button is held (A12).
    private func driveButtons(_ states: [TingButton: Bool] = [:]) {
        let events = buttons.update(states, now: now)
        let keys = events.compactMap { if case .down(let key) = $0 { "\(key)" } else { nil } }
        if !keys.isEmpty {
            let held = states.isEmpty ? "repeat" : states.filter(\.value).keys.map(\.rawValue).sorted().joined(separator: "+")
            log(String(format: "%.2f", now) + " buttons [\(held)] -> \(keys.joined(separator: ", "))")
        }
        KeySender.send(events)
        repeatTimer?.cancel()
        guard let due = buttons.nextDeadline else { return }
        repeatTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, due - (self?.now ?? due))))
            guard !Task.isCancelled else { return }
            self?.driveButtons()
        }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Feeds the talking state to the trigger logic and sends what it returns,
    /// coming back at `nextDeadline` for a deferred toggle (A4).
    private func drive() {
        let events = controller.update(talking: isTalking, now: now)
        log("talking=\(isTalking) active=\(controller.isActive) trusted=\(KeySender.isTrusted) send=\(events)")
        KeySender.send(events)
        deadline?.cancel()
        guard let due = controller.nextDeadline else { return }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, due - (self?.now ?? due))))
            guard !Task.isCancelled else { return }
            self?.drive()
        }
    }

    /// Ends any dictation in progress (pause, lost input, quit: A7, A8).
    private func endDictation(wait: Bool = false) {
        deadline?.cancel()
        let events = controller.stop(now: now)
        if !events.isEmpty { log("stop: send=\(events)") }
        KeySender.send(events, wait: wait)
    }

    func shutdown() {
        endDictation(wait: true)
        stop()
    }

    /// A10. Persisted by device name; nil until the user picks one.
    private(set) var inputChoice = InputChoice(saved: UserDefaults.standard.string(forKey: "inputDevice"))

    /// Switches input: ends any dictation and listens on the new device.
    func setInput(_ name: String) {
        guard name != inputChoice.saved else { return }
        UserDefaults.standard.set(name, forKey: "inputDevice")
        inputChoice = InputChoice(saved: name)
        endDictation()
        start()
    }

    func start() {
        stop()
        if isPaused {
            status = .paused
            return
        }
        // A5: opening the input would trigger the microphone prompt on its own,
        // racing the walkthrough. Wait until the walkthrough has it allowed.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            status = .needsMicrophone
            return
        }
        let inputs = AudioDevices.inputs()
        guard let name = inputChoice.device(in: inputs.map(\.name)),
              let device = inputs.first(where: { $0.name == name })
        else {
            fail("Waiting for \(inputChoice.saved ?? "a CalDigit input")")
            return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        var id = device.id
        let err = AudioUnitSetProperty(
            input.audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard err == noErr else {
            fail("Couldn't select \(device.name) (error \(err))")
            return
        }

        let format = input.outputFormat(forBus: 0)
        let tap = DetectorTap(sampleRate: format.sampleRate, now: now) { [weak self] states, sent in
            Task { @MainActor in
                if Logging.verbose, let self {
                    log(String(format: "tones %@ (main actor %.0f ms late)",
                               states.map { $0 ? "1" : "0" }.joined(), (self.now - sent) * 1000))
                }
                self?.tonesChanged(states)
            }
        }
        Self.install(tap, on: input, format: format)
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("Couldn't start audio: \(error.localizedDescription)")
            return
        }
        self.engine = engine
        status = .listening(device: device.name)
        log("listening on \(device.name) at \(format.sampleRate) Hz")
        watch(device.id, name: device.name, tap: tap)
    }

    /// A7: once a second, checks the device is still there and audio is still
    /// arriving; otherwise ends dictation and reconnects. (Not using
    /// AVAudioEngineConfigurationChange: selecting the device posts one, which
    /// made reconnecting loop forever.)
    private func watch(_ id: AudioDeviceID, name: String, tap: DetectorTap) {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let present = AudioDevices.inputs().contains { $0.id == id }
                if !present || self.now - tap.lastBuffer > 1 {
                    self.fail("Lost \(name); reconnecting")
                    return
                }
            }
        }
    }

    /// Stops listening, ends dictation, and retries every 2 s until the input is back.
    private func fail(_ reason: String) {
        endDictation()
        stop()
        status = .failed(reason)
        log("failed: \(reason)")
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, !self.isPaused else { return }
            self.start()
        }
    }

    /// Nonisolated so the tap block isn't main-actor isolated: CoreAudio calls
    /// it on its own thread.
    private nonisolated static func install(
        _ tap: DetectorTap, on input: AVAudioInputNode, format: AVAudioFormat
    ) {
        input.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
            tap.process(buffer)
        }
    }

    func stop() {
        retry?.cancel()
        watchdog?.cancel()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isTalking = false
        pressedButtons = []
        repeatTimer?.cancel()
        _ = buttons.update(Dictionary(uniqueKeysWithValues: TingButton.allCases.map { ($0, false) }), now: now)
        status = .stopped
    }

    private func pause() {
        endDictation()
        stop()
        status = .paused
    }
}

/// Owns the tone detectors on the audio thread; reports only state changes.
private final class DetectorTap: @unchecked Sendable {
    private var bank: ToneBank
    private var last = [Bool](repeating: false, count: Tones.all.count)
    private let onChange: @Sendable ([Bool], TimeInterval) -> Void
    private let lock = NSLock()
    private var _lastBuffer: TimeInterval
    private var report = Report()

    /// Debug-only tally of what arrived since the last report line.
    private struct Report {
        var since: TimeInterval = 0
        var buffers = 0
        var frames = 0
        var maxGap: TimeInterval = 0
        var peak: Float = 0
    }

    init(sampleRate: Double, now: TimeInterval, onChange: @escaping @Sendable ([Bool], TimeInterval) -> Void) {
        bank = ToneBank(sampleRate: sampleRate, frequencies: Tones.all)
        _lastBuffer = now  // grace period until the first buffer
        self.onChange = onChange
    }

    /// Uptime when audio last arrived; read from the main actor's watchdog.
    var lastBuffer: TimeInterval { lock.withLock { _lastBuffer } }

    func process(_ buffer: AVAudioPCMBuffer) {
        let arrived = ProcessInfo.processInfo.systemUptime
        let previous = lock.withLock {
            defer { _lastBuffer = arrived }
            return _lastBuffer
        }
        guard let channel = buffer.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let states = bank.process(samples)
        if Logging.verbose { tally(samples, gap: arrived - previous, now: arrived, states: states) }
        if states != last {
            last = states
            onChange(states, arrived)
        }
    }

    /// Four times a second: buffer timing, input peak, and each tone's weakest block.
    private func tally(_ samples: UnsafeBufferPointer<Float>, gap: TimeInterval, now: TimeInterval, states: [Bool]) {
        report.buffers += 1
        report.frames += samples.count
        report.maxGap = max(report.maxGap, gap)
        report.peak = samples.reduce(report.peak) { max($0, abs($1)) }
        guard now - report.since >= 0.25 else { return }
        let tones = zip(Tones.all, bank.takeStats()).map { hz, s in
            String(format: "%.0fk %d/%d fail amp>=%.4f ratio>=%.1fdB",
                   hz / 1000, s.failed, s.blocks, s.minAmplitude, s.minRatioDB)
        }
        log(String(format: "audio %d bufs %d frames maxgap %.0f ms peak %.3f | ",
                   report.buffers, report.frames, report.maxGap * 1000, report.peak)
            + tones.joined(separator: " | ") + " | states " + states.map { $0 ? "1" : "0" }.joined())
        report = Report(since: now)
    }
}

/// Diagnostics on stderr (visible when run with `swift run`), stamped with
/// uptime. With verbose logging on they also go to ~/Library/Logs/TingTalk.log,
/// since a Finder-launched app's stderr goes nowhere.
func log(_ message: String) {
    let line = Data(String(format: "[TingTalk] %.3f %@\n", ProcessInfo.processInfo.systemUptime, message).utf8)
    FileHandle.standardError.write(line)
    if Logging.verbose { Logging.append(line) }
}
