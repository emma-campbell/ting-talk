import Testing
@testable import TalkCore

private let optionSpace = Shortcut(keys: [.option, .code(KeyCode.space)])
private let doubleCommand = Shortcut(keys: [.command], taps: 2)
private let fn = Shortcut(keys: [.function])

private func tap(_ keys: [Key]) -> [KeyEvent] {
    keys.map(KeyEvent.down) + [.pause(Shortcut.holdTime)] + keys.reversed().map(KeyEvent.up)
}

@Suite("A3 shortcuts and modes") struct ShortcutsAndModes {
    @Test func toggleChordTapsOnStartAndOnStop() {
        var c = TriggerController(binding: TriggerBinding(shortcut: optionSpace, mode: .toggle))
        #expect(c.update(talking: true, now: 0) == tap([.option, .code(KeyCode.space)]))
        #expect(c.update(talking: false, now: 1) == tap([.option, .code(KeyCode.space)]))
    }

    @Test func doubleTapPausesBetweenTaps() {
        var c = TriggerController(binding: TriggerBinding(shortcut: doubleCommand, mode: .toggle))
        #expect(c.update(talking: true, now: 0)
                == tap([.command]) + [.pause(Shortcut.tapGap)] + tap([.command]))
    }

    @Test func holdModeKeepsKeysDownWhileTalking() {
        var c = TriggerController(binding: TriggerBinding(shortcut: fn, mode: .hold))
        #expect(c.update(talking: true, now: 0) == [.down(.function)])
        #expect(c.update(talking: true, now: 5) == [])
        #expect(c.update(talking: false, now: 10) == [.up(.function)])
    }

    @Test func holdModeReleasesChordsInReverse() {
        var c = TriggerController(binding: TriggerBinding(shortcut: optionSpace, mode: .hold))
        #expect(c.update(talking: true, now: 0) == [.down(.option), .down(.code(KeyCode.space))])
        #expect(c.update(talking: false, now: 1) == [.up(.code(KeyCode.space)), .up(.option)])
    }

    @Test func raycastPresetIsDoubleCommandToggle() {
        #expect(TriggerBinding.raycast == TriggerBinding(shortcut: doubleCommand, mode: .toggle))
    }
}

@Suite("A4 staying in sync") struct StayingInSync {
    @Test func nothingWhileStateIsUnchanged() {
        var c = TriggerController(binding: .raycast)
        #expect(c.update(talking: false, now: 0) == [])
        _ = c.update(talking: true, now: 1)
        #expect(c.update(talking: true, now: 2) == [])
    }

    @Test func toggleInsideTheGapIsDeferredNotDropped() {
        var c = TriggerController(binding: TriggerBinding(shortcut: optionSpace, mode: .toggle))
        _ = c.update(talking: true, now: 0)
        #expect(c.update(talking: false, now: 0.2) == [])
        #expect(c.nextDeadline == 0.4)
        #expect(c.update(talking: false, now: 0.4) == tap([.option, .code(KeyCode.space)]))
        #expect(c.nextDeadline == nil)
    }

    @Test func bounceInsideTheGapNeverToggles() {
        var c = TriggerController(binding: .raycast)
        _ = c.update(talking: true, now: 0)
        #expect(c.update(talking: false, now: 0.1) == [])
        #expect(c.update(talking: true, now: 0.2) == [])
        #expect(c.update(talking: true, now: 0.5) == [])
        #expect(c.isActive)
        #expect(c.nextDeadline == nil)
    }
}

@Suite("A7/A8 stop on pause or unplug") struct StopOnPauseOrUnplug {
    @Test func stopWhileActiveInToggleModeSendsTheStopTap() {
        var c = TriggerController(binding: TriggerBinding(shortcut: optionSpace, mode: .toggle))
        _ = c.update(talking: true, now: 0)
        #expect(c.stop(now: 5) == tap([.option, .code(KeyCode.space)]))
        #expect(!c.isActive)
        #expect(c.update(talking: false, now: 6) == [])
    }

    @Test func stopInsideTheGapWaitsOutTheRemainder() {
        // Binary-exact times so the remaining pause compares exactly.
        var c = TriggerController(
            binding: TriggerBinding(shortcut: optionSpace, mode: .toggle), minToggleGap: 0.5)
        _ = c.update(talking: true, now: 0)
        #expect(c.stop(now: 0.25) == [.pause(0.25)] + tap([.option, .code(KeyCode.space)]))
    }

    @Test func stopInHoldModeReleasesTheKeys() {
        var c = TriggerController(binding: TriggerBinding(shortcut: fn, mode: .hold))
        _ = c.update(talking: true, now: 0)
        #expect(c.stop(now: 0.1) == [.up(.function)])
    }

    @Test func stopWhileIdleDoesNothing() {
        var c = TriggerController(binding: .raycast)
        #expect(c.stop(now: 0) == [])
    }

    @Test func talkingAgainAfterAStopStartsNormally() {
        var c = TriggerController(binding: TriggerBinding(shortcut: optionSpace, mode: .toggle))
        _ = c.update(talking: true, now: 0)
        _ = c.stop(now: 1)
        #expect(c.update(talking: true, now: 2) == tap([.option, .code(KeyCode.space)]))
    }

    @Test func changingTheBindingMidTalkStopsWithTheOldOne() {
        var c = TriggerController(binding: TriggerBinding(shortcut: fn, mode: .hold))
        _ = c.update(talking: true, now: 0)
        #expect(c.setBinding(.raycast, now: 1) == [.up(.function)])
        #expect(!c.isActive)
    }
}
