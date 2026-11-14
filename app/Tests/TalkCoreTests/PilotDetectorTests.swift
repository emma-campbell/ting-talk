import Testing
@testable import TalkCore

/// Feeds audio in 10 ms chunks, like a real input callback, and returns the
/// detector's state at the end of each chunk as (time, talking).
private func run(_ samples: [Float]) -> [(time: Double, talking: Bool)] {
    var detector = PilotDetector(sampleRate: Signals.sampleRate)
    let chunk = 480
    return stride(from: 0, to: samples.count, by: chunk).map { start in
        let end = min(start + chunk, samples.count)
        let talking = detector.process(samples[start..<end])
        return (Double(end) / Signals.sampleRate, talking)
    }
}

/// A1: the state must match `expected` everywhere except within 150 ms after
/// a change in `expected`.
private func expectTracks(
    _ samples: [Float], talkingDuring intervals: [ClosedRange<Double>],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let edges = intervals.flatMap { [$0.lowerBound, $0.upperBound] }
    for (time, talking) in run(samples) {
        if edges.contains(where: { time >= $0 && time < $0 + 0.15 }) { continue }
        let expected = intervals.contains { $0.contains(time) }
        #expect(talking == expected, "at \(time) s", sourceLocation: sourceLocation)
    }
}

private func expectNeverTalking(
    _ samples: [Float], sourceLocation: SourceLocation = #_sourceLocation
) {
    let falseHits = run(samples).filter(\.talking).map(\.time)
    #expect(falseHits.isEmpty, "false hits at \(falseHits.prefix(5))", sourceLocation: sourceLocation)
}

@Suite("A1 detection") struct Detection {
    @Test func recordedPilotWithSpeechThroughTheCalDigit() throws {
        // Ground truth measured from the recording (docs/manual-checks.md, M1).
        expectTracks(try Signals.fixture("caldigit_pilot_speech.wav"),
                     talkingDuring: [1.92...5.00, 6.11...9.95])
    }

    @Test func startsAndStopsWithin150ms() {
        let audio = Signals.silence(seconds: 1)
            + Signals.tone(18_000, amplitude: 0.004, seconds: 2)
            + Signals.silence(seconds: 1)
        expectTracks(audio, talkingDuring: [1.0...3.0])
    }

    @Test func quietPilotUnderNoise() {
        // 10 dB quieter than measured, under broadband noise.
        let pilot = Signals.tone(18_000, amplitude: 0.0015, seconds: 2)
        let audio = Signals.mix(pilot, Signals.noise(amplitude: 0.0005, seconds: 2))
        expectTracks(audio, talkingDuring: [0.0...2.0])
    }

    @Test(arguments: [17_960.0, 18_040.0])
    func slightlyOffFrequencyPilot(frequency: Double) {
        expectTracks(Signals.tone(frequency, amplitude: 0.004, seconds: 2),
                     talkingDuring: [0.0...2.0])
    }

    @Test func pilotUnderLoudSpeechBandAudio() {
        // A loud 300 Hz-ish voice stand-in must not mask the pilot.
        let audio = Signals.mix(Signals.tone(18_000, amplitude: 0.004, seconds: 2),
                                Signals.tone(300, amplitude: 0.5, seconds: 2))
        expectTracks(audio, talkingDuring: [0.0...2.0])
    }
}

@Suite("A2 no false triggers") struct NoFalseTriggers {
    @Test func roomChatter() throws {
        expectNeverTalking(try Signals.fixture("room_chatter.wav"))
    }

    @Test func digitalSilence() {
        expectNeverTalking(Signals.silence(seconds: 2))
    }

    @Test(arguments: [Float(0.0003), 0.003, 0.03, 0.3])
    func whiteNoise(amplitude: Float) {
        expectNeverTalking(Signals.noise(amplitude: amplitude, seconds: 3))
    }

    @Test(arguments: [Float(0.05), 0.9])
    func keyClicks(amplitude: Float) {
        expectNeverTalking(Signals.clicks(every: 0.08, amplitude: amplitude, seconds: 3))
    }

    @Test func fastSweepThroughThePilot() {
        expectNeverTalking(Signals.sweep(from: 8_000, to: 22_000, amplitude: 0.3, seconds: 0.5))
    }
}
