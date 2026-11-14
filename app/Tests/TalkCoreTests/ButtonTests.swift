import Foundation
import Testing
@testable import TalkCore

/// Runs a ToneBank over audio in 10 ms chunks; returns, per channel, whether
/// it was ever on and whether it was on at the end.
private func channels(_ samples: [Float]) -> (everOn: [Bool], end: [Bool]) {
    var bank = ToneBank(sampleRate: Signals.sampleRate, frequencies: Tones.all)
    var everOn = [Bool](repeating: false, count: Tones.all.count)
    var state = everOn
    for start in stride(from: 0, to: samples.count, by: 480) {
        state = bank.process(samples[start..<min(start + 480, samples.count)])
        for i in state.indices where state[i] { everOn[i] = true }
    }
    return (everOn, state)
}

private func tone(_ hz: Double, seconds: Double = 1) -> [Float] {
    Signals.tone(hz, amplitude: 0.004, seconds: seconds)
}

@Suite("A11 multi-tone detection") struct MultiToneDetection {
    @Test(arguments: TingButton.allCases)
    func eachButtonLightsOnlyItsOwnChannel(button: TingButton) {
        let (everOn, end) = channels(tone(button.frequency))
        let mine = Tones.all.firstIndex(of: button.frequency)!
        #expect(end[mine])
        for i in everOn.indices where i != mine {
            #expect(!everOn[i], "channel \(Tones.all[i]) Hz lit by \(button)")
        }
    }

    @Test func allFourTonesAtOnce() {
        let audio = Tones.all.map { tone($0) }.reduce(Signals.silence(seconds: 1), Signals.mix)
        #expect(channels(audio).end == [Bool](repeating: true, count: Tones.all.count))
    }

    @Test func buttonWhileTalkingOverLoudVoice() {
        let audio = [tone(Tones.talk), tone(TingButton.middle.frequency),
                     Signals.tone(300, amplitude: 0.5, seconds: 1)]
            .reduce(Signals.silence(seconds: 1), Signals.mix)
        let end = channels(audio).end
        #expect(end == Tones.all.map { $0 == Tones.talk || $0 == TingButton.middle.frequency })
    }

    @Test func recordedTalkFixtureNeverLightsAButton() throws {
        let (everOn, _) = channels(try Signals.fixture("caldigit_pilot_speech.wav"))
        for button in TingButton.allCases {
            #expect(!everOn[Tones.all.firstIndex(of: button.frequency)!], "\(button)")
        }
    }

    @Test func roomChatterAndNoiseLightNothing() throws {
        #expect(!channels(try Signals.fixture("room_chatter.wav")).everOn.contains(true))
        #expect(!channels(Signals.noise(amplitude: 0.3, seconds: 3)).everOn.contains(true))
    }
}

private func tap(_ key: Key) -> [KeyEvent] {
    [.down(key), .pause(Shortcut.holdTime), .up(key)]
}

@Suite("A11 button mapping") struct ButtonMappingTests {
    @Test func defaultSuitsClaudeCodeQuestions() {
        #expect(ButtonMapping.default.key(for: .top) == .code(KeyCode.upArrow))
        #expect(ButtonMapping.default.key(for: .middle) == .code(KeyCode.downArrow))
        #expect(ButtonMapping.default.key(for: .bottom) == .code(KeyCode.returnKey))
    }

    @Test func onePressIsOneTapAndHoldingDoesNotRepeat() {
        var m = ButtonMapper(mapping: .default)
        #expect(m.update([.middle: true]) == tap(.code(KeyCode.downArrow)))
        #expect(m.update([.middle: true]) == [])
        #expect(m.update([.middle: false]) == [])
        #expect(m.update([.middle: true]) == tap(.code(KeyCode.downArrow)))
    }

    @Test func simultaneousPressesTapInButtonOrder() {
        var m = ButtonMapper(mapping: .default)
        #expect(m.update([.bottom: true, .top: true])
                == tap(.code(KeyCode.upArrow)) + tap(.code(KeyCode.returnKey)))
    }

    @Test func unmappedButtonDoesNothing() {
        var mapping = ButtonMapping.default
        mapping.set(nil, for: .bottom)
        var m = ButtonMapper(mapping: mapping)
        #expect(m.update([.bottom: true]) == [])
    }

    @Test func mappingSurvivesSaveAndLoad() throws {
        var mapping = ButtonMapping.default
        mapping.set(.code(KeyCode.escape), for: .top)
        mapping.set(nil, for: .middle)
        let data = try JSONEncoder().encode(mapping)
        #expect(try JSONDecoder().decode(ButtonMapping.self, from: data) == mapping)
    }

    @Test func tonesStayClearOfEachOthersNeighbourBins() {
        // The detector compares each tone with bins ±400 and ±800 Hz away;
        // another tone sitting there would mask it.
        for a in Tones.all {
            for b in Tones.all where a != b {
                for offset in [-800.0, -400, 400, 800] {
                    #expect(abs(a + offset - b) >= 150, "\(a) neighbour hits \(b)")
                }
            }
        }
    }
}
