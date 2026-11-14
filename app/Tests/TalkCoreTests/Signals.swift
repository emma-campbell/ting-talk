import Foundation

/// Test audio: recorded fixtures from tests/fixtures/ and synthetic signals.
enum Signals {
    static let sampleRate = 48_000.0

    /// Loads a 16-bit mono PCM WAV from the repo's tests/fixtures/.
    static func fixture(_ name: String) throws -> [Float] {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TalkCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // app
            .deletingLastPathComponent()  // repo root
        let data = try Data(contentsOf: repo.appending(path: "tests/fixtures/\(name)"))
        // Plain 44-byte header, as written by Python's wave module.
        return data.dropFirst(44).withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32768 }
        }
    }

    static func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: count(seconds))
    }

    static func tone(_ frequency: Double, amplitude: Float, seconds: Double) -> [Float] {
        (0..<count(seconds)).map {
            amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate))
        }
    }

    /// Uniform white noise, seeded so failures are reproducible.
    static func noise(amplitude: Float, seconds: Double, seed: UInt64 = 1) -> [Float] {
        var rng = SplitMix64(seed: seed)
        return (0..<count(seconds)).map { _ in amplitude * Float.random(in: -1...1, using: &rng) }
    }

    /// Single-sample impulses, like key clicks.
    static func clicks(every interval: Double, amplitude: Float, seconds: Double) -> [Float] {
        var out = silence(seconds: seconds)
        let step = count(interval)
        for i in stride(from: 0, to: out.count, by: step) { out[i] = amplitude }
        return out
    }

    /// Linear chirp from `from` to `to` Hz.
    static func sweep(from: Double, to: Double, amplitude: Float, seconds: Double) -> [Float] {
        let n = count(seconds)
        let rate = (to - from) / seconds
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            return amplitude * Float(sin(2 * .pi * (from * t + rate * t * t / 2)))
        }
    }

    static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        zip(a, b).map { $0 + $1 }
    }

    static func count(_ seconds: Double) -> Int { Int(seconds * sampleRate) }
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
