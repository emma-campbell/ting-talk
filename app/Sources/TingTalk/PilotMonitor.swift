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
    private(set) var isTalking = false {
        didSet { if isTalking != oldValue { drive() } }
    }

    private var engine: AVAudioEngine?
    private var controller = TriggerController(binding: .raycast)
    private var deadline: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    var binding: TriggerBinding { controller.binding }

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

    /// Called with every tone's state, in `Tones.all` order, when any changes.
    private func tonesChanged(_ states: [Bool]) {
        isTalking = states[0]
        let pressed = Dictionary(uniqueKeysWithValues: zip(TingButton.allCases, states.dropFirst()))
        let events = buttons.update(pressed)
        if !events.isEmpty { log("buttons=\(pressed.filter(\.value).keys.map(\.rawValue)) send=\(events)") }
        KeySender.send(events)
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
        let tap = DetectorTap(sampleRate: format.sampleRate, now: now) { [weak self] states in
            Task { @MainActor in self?.tonesChanged(states) }
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
        _ = buttons.update(Dictionary(uniqueKeysWithValues: TingButton.allCases.map { ($0, false) }))
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
    private let onChange: @Sendable ([Bool]) -> Void
    private let lock = NSLock()
    private var _lastBuffer: TimeInterval

    init(sampleRate: Double, now: TimeInterval, onChange: @escaping @Sendable ([Bool]) -> Void) {
        bank = ToneBank(sampleRate: sampleRate, frequencies: Tones.all)
        _lastBuffer = now  // grace period until the first buffer
        self.onChange = onChange
    }

    /// Uptime when audio last arrived; read from the main actor's watchdog.
    var lastBuffer: TimeInterval { lock.withLock { _lastBuffer } }

    func process(_ buffer: AVAudioPCMBuffer) {
        let arrived = ProcessInfo.processInfo.systemUptime
        lock.withLock { _lastBuffer = arrived }
        guard let channel = buffer.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let states = bank.process(samples)
        if states != last {
            last = states
            onChange(states)
        }
    }
}

/// Diagnostics on stderr (visible when run with `swift run`).
func log(_ message: String) {
    FileHandle.standardError.write(Data("[TingTalk] \(message)\n".utf8))
}
