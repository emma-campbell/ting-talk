// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TingTalk",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (pilot detection, trigger state machine); no UI or audio I/O.
        .target(name: "TalkCore"),
        .testTarget(name: "TalkCoreTests", dependencies: ["TalkCore"]),
        // The menu-bar app: audio input, UI, and (later) sending triggers.
        .executableTarget(name: "TingTalk", dependencies: ["TalkCore"]),
    ]
)
