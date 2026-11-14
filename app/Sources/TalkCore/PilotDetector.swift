import Foundation

/// Detects the Ting's pilot tone, which plays exactly while the user is
/// talking (handle in, plus the release tail).
///
/// Every hop, a Hann-windowed block is measured at the pilot frequency and at
/// four neighbours. A block counts as "pilot" only if the pilot bin is both
/// loud enough and well above its neighbours. Broadband sound (speech, noise,
/// clicks) lights up the neighbours too, so it fails the second test. The state
/// changes only after several blocks in a row agree, which rejects brief
/// coincidences such as a fast sweep or a noise spike.
public struct PilotDetector {
    public private(set) var isTalking = false

    private static let blockSize = 1024  // ~21 ms at 48 kHz
    private static let hop = 512
    /// Pilot power must exceed the mean neighbour power by this factor (12 dB).
    private let minRatio: Float = 15.85
    private let minPower: Float
    /// Consecutive agreeing blocks needed to change state (~43 ms of hops).
    private let blocksToSwitch = 4

    private let pilotBin: Bin
    private let neighbourBins: [Bin]
    private var buffer: [Float] = []
    private var streak = 0

    /// - Parameter minAmplitude: quietest pilot (peak, full scale = 1) that
    ///   counts. The pilot measured through the CalDigit is ~0.004.
    public init(
        sampleRate: Double, frequency: Double = 18_000, minAmplitude: Float = 0.0007
    ) {
        let n = Self.blockSize
        let window = (0..<n).map {
            Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n - 1)))
        }
        pilotBin = Bin(frequency: frequency, sampleRate: sampleRate, window: window)
        neighbourBins = [-800.0, -400, 400, 800].map {
            Bin(frequency: frequency + $0, sampleRate: sampleRate, window: window)
        }
        // A Hann-windowed sine of amplitude A sums to about A * N / 4 at its bin.
        let magnitude = minAmplitude * Float(n) / 4
        minPower = magnitude * magnitude
    }

    /// Feed the next samples; returns whether the user is talking.
    @discardableResult
    public mutating func process(_ samples: some Collection<Float>) -> Bool {
        buffer.append(contentsOf: samples)
        while buffer.count >= Self.blockSize {
            update(pilotPresent: isPilot(buffer[0..<Self.blockSize]))
            buffer.removeFirst(Self.hop)
        }
        return isTalking
    }

    private func isPilot(_ block: ArraySlice<Float>) -> Bool {
        let pilot = pilotBin.power(of: block)
        guard pilot >= minPower else { return false }
        let neighbours = neighbourBins.reduce(0) { $0 + $1.power(of: block) } / 4
        return pilot >= minRatio * neighbours
    }

    private mutating func update(pilotPresent: Bool) {
        if pilotPresent == isTalking {
            streak = 0
            return
        }
        streak += 1
        if streak >= blocksToSwitch {
            isTalking = pilotPresent
            streak = 0
        }
    }
}

/// A single windowed DFT bin, with the window folded into the basis.
private struct Bin {
    let cosines: [Float]
    let sines: [Float]

    init(frequency: Double, sampleRate: Double, window: [Float]) {
        let w = 2 * .pi * frequency / sampleRate
        cosines = window.indices.map { window[$0] * Float(cos(w * Double($0))) }
        sines = window.indices.map { window[$0] * Float(sin(w * Double($0))) }
    }

    func power(of block: ArraySlice<Float>) -> Float {
        var re: Float = 0
        var im: Float = 0
        for (i, x) in zip(cosines.indices, block) {
            re += x * cosines[i]
            im += x * sines[i]
        }
        return re * re + im * im
    }
}
