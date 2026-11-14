/// The first-run walkthrough's progress (A5): one permission at a time, then an
/// optional live test. Two system prompts at once race each other, so the app
/// asks for nothing until the walkthrough reaches that step.
public struct SetupState: Equatable, Sendable {
    public enum Microphone: Sendable { case notAsked, allowed, denied }
    public enum Step: Sendable { case microphone, accessibility, test, done }

    public var microphone: Microphone
    public var accessibility: Bool
    public private(set) var heardSqueeze = false
    public private(set) var heardButton = false

    public init(microphone: Microphone, accessibility: Bool) {
        self.microphone = microphone
        self.accessibility = accessibility
    }

    public var currentStep: Step {
        // A denied microphone can only be fixed in System Settings, so the
        // walkthrough stays on that step until it's allowed.
        if microphone != .allowed { return .microphone }
        if !accessibility { return .accessibility }
        return heardSqueeze && heardButton ? .done : .test
    }

    /// Both permissions granted. The test step is optional.
    public var isComplete: Bool { microphone == .allowed && accessibility }

    /// Listening needs only the microphone; keys need Accessibility too.
    public var canListen: Bool { microphone == .allowed }

    /// Open the window on launch, and again whenever a permission goes missing.
    public var needsWindow: Bool { !isComplete }

    public mutating func heard(talking: Bool, buttonPressed: Bool) {
        if talking { heardSqueeze = true }
        if buttonPressed { heardButton = true }
    }
}
