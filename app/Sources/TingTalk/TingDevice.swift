import AppKit
import Observation
import TalkCore

/// The Ting's CIRCUITPY drive, when it's connected by USB-C (A9). The coiled
/// cable only carries the Ting's audio to the Mac, so this is the only way to
/// change settings on the device.
@MainActor @Observable
final class TingDevice {
    enum State: Equatable {
        case disconnected
        /// Happens when USB reconnects while the Ting runs on battery; a
        /// restart (power off, squeeze) makes it writable again.
        case readOnly
        case connected(DeviceSettings)
    }

    private(set) var state = State.disconnected
    private(set) var lastError: String?
    private var volume: URL?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        lastError = nil
        volume = Self.findTing()
        guard let volume else {
            state = .disconnected
            return
        }
        guard FileManager.default.isWritableFile(atPath: volume.path) else {
            state = .readOnly
            return
        }
        state = .connected(DeviceSettings.parse(readSettings(volume)))
    }

    /// Writes the timeout; the Ting reloads its code when the file changes.
    func setSleepAfter(_ seconds: Int) {
        guard let volume, case .connected = state else { return }
        let updated = DeviceSettings.updating(readSettings(volume), sleepAfter: seconds)
        do {
            // Not atomic: a temp-file-and-rename on this FAT drive just makes
            // CircuitPython reload twice.
            try Data(updated.utf8).write(to: volume.appending(path: "settings.toml"))
            state = .connected(DeviceSettings.parse(updated))
            log("wrote \(DeviceSettings.sleepKey) = \(seconds)")
        } catch {
            lastError = "Couldn't write to the Ting: \(error.localizedDescription)"
            refresh()
        }
    }

    private func readSettings(_ volume: URL) -> String {
        (try? String(contentsOf: volume.appending(path: "settings.toml"), encoding: .utf8)) ?? ""
    }

    private static func findTing() -> URL? {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return volumes.first { url in
            guard let bootOut = try? String(
                contentsOf: url.appending(path: "boot_out.txt"), encoding: .utf8)
            else { return false }
            return DeviceSettings.isTing(bootOut: bootOut)
        }
    }
}
