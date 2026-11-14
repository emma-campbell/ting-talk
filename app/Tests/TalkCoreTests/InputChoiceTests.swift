import Testing
@testable import TalkCore

@Suite("A10 input selection") struct InputSelection {
    let available = ["MacBook Pro Microphone", "CalDigit Thunderbolt 3 Audio", "Insta360 Link 2"]

    @Test func defaultsToTheCalDigitWhenNothingIsChosen() {
        #expect(InputChoice(saved: nil).device(in: available) == "CalDigit Thunderbolt 3 Audio")
    }

    @Test func noDefaultWithoutACalDigit() {
        #expect(InputChoice(saved: nil).device(in: ["MacBook Pro Microphone"]) == nil)
    }

    @Test func usesTheSavedInputWhenConnected() {
        #expect(InputChoice(saved: "Insta360 Link 2").device(in: available) == "Insta360 Link 2")
    }

    @Test func neverFallsBackWhenTheSavedInputIsMissing() {
        #expect(InputChoice(saved: "USB Audio Device").device(in: available) == nil)
    }

    @Test func menuListsInputsAndSelectsTheCurrentOne() {
        let menu = InputChoice(saved: "Insta360 Link 2").menu(available: available)
        #expect(menu.items.map(\.title) == available)
        #expect(menu.selected == "Insta360 Link 2")
    }

    @Test func menuKeepsAMissingSavedInputAsNotConnected() {
        let menu = InputChoice(saved: "USB Audio Device").menu(available: available)
        #expect(menu.items.last == .init(name: "USB Audio Device", connected: false))
        #expect(menu.items.last?.title == "USB Audio Device (not connected)")
        #expect(menu.selected == "USB Audio Device")
    }

    @Test func menuSelectsTheDefaultWhenNothingIsSaved() {
        #expect(InputChoice(saved: nil).menu(available: available).selected
                == "CalDigit Thunderbolt 3 Audio")
    }
}
