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

    @Test func onePressIsOneTapAndQuickReleaseNeverRepeats() {
        var m = ButtonMapper(mapping: .default)
        #expect(m.update([.middle: true], now: 0) == tap(.code(KeyCode.downArrow)))
        #expect(m.update([.middle: true], now: 0.1) == [])
        #expect(m.update([.middle: false], now: 0.2) == [])
        #expect(m.nextDeadline == nil)
        #expect(m.update([.middle: true], now: 1) == tap(.code(KeyCode.downArrow)))
    }

    @Test func simultaneousPressesTapInButtonOrder() {
        var mapping = ButtonMapping.default
        mapping.set(.code(KeyCode.tab), for: .bottom)
        var m = ButtonMapper(mapping: mapping)
        #expect(m.update([.bottom: true, .top: true], now: 0)
                == tap(.code(KeyCode.upArrow)) + tap(.code(KeyCode.tab)))
    }

    @Test func unmappedButtonDoesNothing() {
        var mapping = ButtonMapping.default
        mapping.set(nil, for: .bottom)
        var m = ButtonMapper(mapping: mapping)
        #expect(m.update([.bottom: true], now: 0) == [])
        #expect(m.nextDeadline == nil)
    }

    @Test func mappingSurvivesSaveAndLoad() throws {
        var mapping = ButtonMapping.default
        mapping.set(.code(KeyCode.escape), for: .top)
        mapping.set(nil, for: .middle)
        mapping.setRepeats(true, for: .top)
        mapping.repeatDelay = 0.6
        mapping.repeatInterval = 0.2
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

@Suite("A12 auto-repeat") struct AutoRepeat {
    // Binary-exact times and timings so deadlines compare exactly.
    private func mapper() -> ButtonMapper {
        var mapping = ButtonMapping.default
        mapping.repeatDelay = 0.5
        mapping.repeatInterval = 0.125
        return ButtonMapper(mapping: mapping)
    }

    @Test func defaultsAreKeyboardLike() {
        #expect(ButtonMapping.default.repeatDelay == 0.4)
        #expect(ButtonMapping.default.repeatInterval == 0.1)
        #expect(ButtonMapping.repeatDelayChoices.contains(0.4))
        #expect(ButtonMapping.repeatIntervalChoices.contains(0.1))
    }

    @Test func arrowsRepeatByDefaultAndReturnDoesNot() {
        #expect(ButtonMapping.default.repeats(for: .top))
        #expect(ButtonMapping.default.repeats(for: .middle))
        #expect(!ButtonMapping.default.repeats(for: .bottom))
    }

    @Test func choosingAKeyResetsItsRepeatDefault() {
        var mapping = ButtonMapping.default
        mapping.set(.code(KeyCode.returnKey), for: .top)
        #expect(!mapping.repeats(for: .top))
        mapping.set(.code(KeyCode.leftArrow), for: .bottom)
        #expect(mapping.repeats(for: .bottom))
    }

    @Test func heldArrowRepeatsAfterTheDelayAtTheInterval() {
        var m = mapper()
        let down = tap(.code(KeyCode.downArrow))
        #expect(m.update([.middle: true], now: 0) == down)
        #expect(m.nextDeadline == 0.5)
        #expect(m.update([.middle: true], now: 0.25) == [])
        #expect(m.update([.middle: true], now: 0.5) == down)
        #expect(m.nextDeadline == 0.625)
        #expect(m.update([.middle: true], now: 0.625) == down)
        #expect(m.update([.middle: false], now: 0.7) == [])
        #expect(m.nextDeadline == nil)
        #expect(m.update([.middle: false], now: 1.0) == [])
    }

    @Test func repeatCanBeTurnedOnForOtherKeys() {
        var mapping = ButtonMapping.default
        mapping.set(.code(KeyCode.tab), for: .bottom)
        #expect(!mapping.repeats(for: .bottom))
        mapping.setRepeats(true, for: .bottom)
        var m = ButtonMapper(mapping: mapping)
        _ = m.update([.bottom: true], now: 0)
        #expect(m.update([.bottom: true], now: 0.4) == tap(.code(KeyCode.tab)))
    }

    @Test func fallingBehindSendsOneRepeatNotABurst() {
        var m = mapper()
        _ = m.update([.middle: true], now: 0)
        #expect(m.update([.middle: true], now: 2.0) == tap(.code(KeyCode.downArrow)))
        #expect(m.nextDeadline == 2.125)
    }

    @Test func eachHeldButtonRepeatsOnItsOwnSchedule() {
        var m = mapper()
        _ = m.update([.top: true], now: 0)
        _ = m.update([.top: true, .middle: true], now: 0.25)
        #expect(m.nextDeadline == 0.5)
        #expect(m.update([.top: true, .middle: true], now: 0.5) == tap(.code(KeyCode.upArrow)))
        #expect(m.nextDeadline == 0.625)
        #expect(m.update([.top: true, .middle: true], now: 0.75)
                == tap(.code(KeyCode.upArrow)) + tap(.code(KeyCode.downArrow)))
    }
}

@Suite("A13 Enter and Escape need a deliberate click") struct ConfirmKeys {
    @Test(arguments: [KeyCode.returnKey, KeyCode.escape])
    func quickClickSendsOnRelease(code: UInt16) {
        var mapping = ButtonMapping.default
        mapping.set(.code(code), for: .bottom)
        var m = ButtonMapper(mapping: mapping)
        #expect(m.update([.bottom: true], now: 0) == [])
        #expect(m.update([.bottom: false], now: 0.25) == tap(.code(code)))
    }

    @Test(arguments: [KeyCode.returnKey, KeyCode.escape])
    func holdingCancels(code: UInt16) {
        var mapping = ButtonMapping.default
        mapping.set(.code(code), for: .bottom)
        var m = ButtonMapper(mapping: mapping)
        _ = m.update([.bottom: true], now: 0)
        #expect(m.nextDeadline == nil)
        #expect(m.update([.bottom: true], now: 2) == [])
        #expect(m.update([.bottom: false], now: 2.5) == [])
    }

    @Test func justUnderTheLimitStillCounts() {
        var m = ButtonMapper(mapping: .default)
        _ = m.update([.bottom: true], now: 0)
        #expect(m.update([.bottom: false], now: ButtonMapping.confirmMaxHold - 0.01)
                == tap(.code(KeyCode.returnKey)))
    }

    @Test func confirmKeysCannotRepeat() {
        var mapping = ButtonMapping.default
        mapping.setRepeats(true, for: .bottom)
        #expect(!mapping.repeats(for: .bottom))
        #expect(!ButtonMapping.canRepeat(.code(KeyCode.escape)))
        #expect(ButtonMapping.canRepeat(.code(KeyCode.downArrow)))
    }

    @Test func anyButtonMappedToEnterBehavesTheSame() {
        var mapping = ButtonMapping.default
        mapping.set(.code(KeyCode.returnKey), for: .top)
        var m = ButtonMapper(mapping: mapping)
        #expect(m.update([.top: true], now: 0) == [])
        #expect(m.update([.top: false], now: 0.25) == tap(.code(KeyCode.returnKey)))
    }

    @Test func otherButtonsKeepWorkingWhileEnterIsHeld() {
        var m = ButtonMapper(mapping: .default)
        _ = m.update([.bottom: true], now: 0)
        #expect(m.update([.bottom: true, .middle: true], now: 0.25)
                == tap(.code(KeyCode.downArrow)))
    }
}
