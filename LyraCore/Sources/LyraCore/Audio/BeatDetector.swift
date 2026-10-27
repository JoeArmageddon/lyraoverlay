import Foundation

/// Finds onsets in the spectral-flux signal and estimates the tempo from their spacing.
public struct BeatDetector {
    /// Shortest gap between two beats (about 240 BPM).
    static let minInterval = 0.25
    /// How much history sets the adaptive threshold, in frames (about 1.5 s).
    static let historyFrames = 140
    static let onsetWindow = 12.0   // seconds of onsets kept for tempo
    static let tempoRange = 70.0...180.0

    private var fluxHistory: [Float] = []
    private var last2: (flux: Float, time: Double, rms: Float)?
    private var last1: (flux: Float, time: Double, rms: Float)?
    private var lastBeatTime = -1.0
    public private(set) var onsets: [Double] = []
    public private(set) var bpm: Double?

    public init() {}

    /// Returns the time of a beat if this frame confirms one. A beat is confirmed one
    /// frame late (about 10 ms), because it takes the next frame to see a peak.
    public mutating func process(_ frame: SpectralFrame) -> Double? {
        defer {
            last2 = last1
            last1 = (frame.flux, frame.time, frame.rms)
            fluxHistory.append(frame.flux)
            if fluxHistory.count > Self.historyFrames { fluxHistory.removeFirst() }
        }
        guard let prev = last1, let older = last2, fluxHistory.count >= 20 else { return nil }

        // `prev` is a beat if it is a local peak that clears the adaptive threshold.
        let isPeak = prev.flux > older.flux && prev.flux >= frame.flux
        guard isPeak, prev.rms > 0.004 else { return nil }

        let mean = fluxHistory.reduce(0, +) / Float(fluxHistory.count)
        let variance = fluxHistory.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(fluxHistory.count)
        let threshold = mean + 1.4 * sqrt(variance) + 0.15
        guard prev.flux > threshold, prev.time - lastBeatTime >= Self.minInterval else { return nil }

        lastBeatTime = prev.time
        onsets.append(prev.time)
        onsets.removeAll { $0 < prev.time - Self.onsetWindow }
        updateTempo()
        return prev.time
    }

    public mutating func reset() {
        self = BeatDetector()
    }

    // MARK: - Tempo

    /// Histogram of spacings between onsets (neighbors up to three apart, folded into
    /// the usual tempo range), smoothed; the peak is the tempo.
    private mutating func updateTempo() {
        guard onsets.count >= 6 else { return }
        var histogram = [Double](repeating: 0, count: 241)   // 1 BPM bins
        for i in 0..<onsets.count {
            for gap in 1...3 where i + gap < onsets.count {
                let interval = onsets[i + gap] - onsets[i]
                guard interval > 0.1 else { continue }
                var candidate = 60 / interval * Double(gap)
                while candidate < Self.tempoRange.lowerBound { candidate *= 2 }
                while candidate > Self.tempoRange.upperBound { candidate /= 2 }
                let bin = Int(candidate.rounded())
                // Adjacent beats vote far more than distant ones; equal votes let a 3:2
                // relationship (every third beat vs every second) outweigh the real pulse.
                if bin < histogram.count { histogram[bin] += 1 / Double(gap * gap) }
            }
        }
        // Smooth with a +-2 BPM window so slightly drifting beats still vote together.
        var best = 0.0, bestBin = 0
        for b in 60...200 {
            var s = 0.0
            for d in -2...2 { s += histogram[b + d] * (1 - 0.2 * Double(abs(d))) }
            if s > best { best = s; bestBin = b }
        }
        guard bestBin > 0 else { return }
        // Refine to the weighted center of the peak, then ease toward it.
        var num = 0.0, den = 0.0
        for d in -2...2 { num += Double(bestBin + d) * histogram[bestBin + d]; den += histogram[bestBin + d] }
        let estimate = den > 0 ? num / den : Double(bestBin)
        bpm = bpm.map { $0 * 0.7 + estimate * 0.3 } ?? estimate
    }
}
