import Testing
@testable import TalkCore

@Suite("A5 first-run walkthrough") struct Walkthrough {
    @Test func startsWithTheMicrophone() {
        let s = SetupState(microphone: .notAsked, accessibility: false)
        #expect(s.currentStep == .microphone)
        #expect(!s.isComplete)
    }

    @Test func accessibilityComesOnlyAfterTheMicrophoneIsAnswered() {
        #expect(SetupState(microphone: .notAsked, accessibility: false).currentStep == .microphone)
        #expect(SetupState(microphone: .allowed, accessibility: false).currentStep == .accessibility)
    }

    @Test func aDeniedMicrophoneStaysOnTheMicrophoneStep() {
        // Denied can only be fixed in System Settings, so the step stays put.
        let s = SetupState(microphone: .denied, accessibility: true)
        #expect(s.currentStep == .microphone)
        #expect(!s.isComplete)
    }

    @Test func bothPermissionsMoveOnToTheOptionalTest() {
        let s = SetupState(microphone: .allowed, accessibility: true)
        #expect(s.currentStep == .test)
        #expect(s.isComplete)
    }

    @Test func testStepTicksOffSqueezeAndButtonSeparately() {
        var s = SetupState(microphone: .allowed, accessibility: true)
        s.heard(talking: true, buttonPressed: false)
        #expect(s.heardSqueeze && !s.heardButton)
        #expect(s.currentStep == .test)
        s.heard(talking: false, buttonPressed: true)
        #expect(s.heardSqueeze && s.heardButton)
        #expect(s.currentStep == .done)
    }

    @Test func listeningWaitsForTheMicrophone() {
        #expect(!SetupState(microphone: .notAsked, accessibility: true).canListen)
        #expect(!SetupState(microphone: .denied, accessibility: true).canListen)
        #expect(SetupState(microphone: .allowed, accessibility: false).canListen)
    }

    @Test(arguments: [
        (SetupState.Microphone.notAsked, false, true),
        (.allowed, false, true),
        (.denied, true, true),
        (.allowed, true, false),
    ])
    func windowOpensWheneverAPermissionIsMissing(
        mic: SetupState.Microphone, accessibility: Bool, shows: Bool
    ) {
        #expect(SetupState(microphone: mic, accessibility: accessibility).needsWindow == shows)
    }
}
