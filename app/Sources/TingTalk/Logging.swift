import Foundation

/// Verbose diagnostics: audio timing, each tone's weakest block, and key
/// posting, four times a second. Off by default. Turned on in Settings or with
/// the TINGTALK_DEBUG environment variable.
enum Logging {
    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/TingTalk.log")

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _verbose =
        UserDefaults.standard.bool(forKey: "verboseLogging")
        || ProcessInfo.processInfo.environment["TINGTALK_DEBUG"] != nil
    nonisolated(unsafe) private static var handle: FileHandle?

    /// Read from the audio thread, so it's a locked copy rather than UserDefaults.
    static var verbose: Bool {
        get { lock.withLock { _verbose } }
        set {
            UserDefaults.standard.set(newValue, forKey: "verboseLogging")
            lock.withLock {
                _verbose = newValue
                if !newValue {
                    try? handle?.close()
                    handle = nil
                }
            }
            log("verbose logging \(newValue ? "on" : "off")")
        }
    }

    static func append(_ line: Data) {
        lock.withLock {
            if handle == nil {
                if !FileManager.default.fileExists(atPath: file.path) {
                    FileManager.default.createFile(atPath: file.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: file)
                _ = try? handle?.seekToEnd()
            }
            try? handle?.write(contentsOf: line)
        }
    }
}
