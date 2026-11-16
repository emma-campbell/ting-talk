import Foundation
import Testing
@testable import TalkCore

private func names(_ code: UInt16) -> String { code == 0x00 ? "A" : "?" }

@Suite("A3 presets") struct Presets {
    @Test func raycastIsTheFirstPresetAndTheDefault() {
        #expect(TriggerPreset.all.first?.binding == .raycast)
        #expect(TriggerBinding.default == .raycast)
    }

    @Test func aBindingMatchingAPresetIsNamedForIt() {
        #expect(TriggerPreset.matching(.raycast)?.name == "Raycast")
    }

    @Test func anyOtherBindingIsCustom() {
        let custom = TriggerBinding(shortcut: Shortcut(keys: [.control, .code(0x00)]), mode: .hold)
        #expect(TriggerPreset.matching(custom) == nil)
    }

    @Test func presetNamesAreUnique() {
        #expect(Set(TriggerPreset.all.map(\.name)).count == TriggerPreset.all.count)
    }

    @Test func bindingSurvivesARoundTrip() throws {
        let binding = TriggerBinding(shortcut: Shortcut(keys: [.option, .code(KeyCode.space)], taps: 2), mode: .hold)
        let data = try JSONEncoder().encode(binding)
        #expect(try JSONDecoder().decode(TriggerBinding.self, from: data) == binding)
    }
}

@Suite("A3 shortcut labels") struct Labels {
    @Test func chordUsesSymbolsThenTheKeyName() {
        #expect(Shortcut(keys: [.control, .option, .code(0x00)]).label(keyName: names) == "⌃⌥A")
    }

    @Test func doubleTapRepeatsTheKeys() {
        #expect(Shortcut(keys: [.option], taps: 2).label(keyName: names) == "⌥ + ⌥")
        #expect(Shortcut(keys: [.control, .code(0x00)], taps: 2).label(keyName: names) == "⌃A + ⌃A")
    }

    @Test func namedKeysDontNeedTheLayout() {
        #expect(Shortcut(keys: [.option, .code(KeyCode.space)]).label(keyName: names) == "⌥Space")
        #expect(Shortcut(keys: [.function]).label(keyName: names) == "fn")
        #expect(Shortcut(keys: [.code(KeyCode.f5)]).label(keyName: names) == "F5")
    }

    @Test func bindingLabelAddsTheMode() {
        let binding = TriggerBinding(shortcut: Shortcut(keys: [.function]), mode: .hold)
        #expect(binding.label(keyName: names) == "hold fn")
        #expect(TriggerBinding.raycast.label(keyName: names) == "⌘ + ⌘, toggle")
    }
}

@Suite("A3 recording a custom shortcut") struct Recording {
    @Test func aKeyWithModifiersHeldIsAChord() {
        var r = ShortcutRecorder()
        #expect(r.modifiersChanged([.control]) == nil)
        #expect(r.modifiersChanged([.control, .option]) == nil)
        #expect(r.keyDown(0x00) == .keys([.control, .option, .code(0x00)]))
    }

    @Test func modifiersComeOutInMacOSOrderWhateverThePressOrder() {
        var r = ShortcutRecorder()
        _ = r.modifiersChanged([.command])
        _ = r.modifiersChanged([.command, .shift])
        _ = r.modifiersChanged([.command, .shift, .control])
        #expect(r.keyDown(0x00) == .keys([.control, .shift, .command, .code(0x00)]))
    }

    @Test func aKeyAloneIsAccepted() {
        var r = ShortcutRecorder()
        #expect(r.keyDown(KeyCode.f5) == .keys([.code(KeyCode.f5)]))
    }

    @Test func modifiersPressedAndReleasedAloneAreAModifierShortcut() {
        var r = ShortcutRecorder()
        _ = r.modifiersChanged([.function])
        #expect(r.modifiersChanged([]) == .keys([.function]))
    }

    @Test func aModifierOnlyShortcutKeepsTheMostThatWereHeld() {
        var r = ShortcutRecorder()
        _ = r.modifiersChanged([.control])
        _ = r.modifiersChanged([.control, .option])
        _ = r.modifiersChanged([.option])
        #expect(r.modifiersChanged([]) == .keys([.control, .option]))
    }

    @Test func modifiersReleasedAfterAChordDontRecordAgain() {
        var r = ShortcutRecorder()
        _ = r.modifiersChanged([.option])
        _ = r.keyDown(KeyCode.space)
        #expect(r.modifiersChanged([]) == nil)
    }

    @Test func escapeAloneCancels() {
        var r = ShortcutRecorder()
        #expect(r.keyDown(KeyCode.escape) == .cancelled)
    }

    @Test func escapeWithAModifierIsAChord() {
        var r = ShortcutRecorder()
        _ = r.modifiersChanged([.option])
        #expect(r.keyDown(KeyCode.escape) == .keys([.option, .code(KeyCode.escape)]))
    }
}
