import Foundation

/// What a stretch of a song sounded like, boiled down.
public struct AudioSummary: Equatable, Sendable {
    /// Mean of the slow energy feature, 0...1. The analyzer scales each band against its own recent
    /// peak, so this is "how full the song is relative to its own loudest moments", not absolute volume.
    public var energy: Double
    /// Bass / (bass + mid + treble), averaged. About 0.33 for a flat spectrum.
    public var bassShare: Double
    /// Mean spectral brightness, 0 dark and bassy ... 1 bright and airy.
    public var brightness: Double
    /// Stable tempo in BPM, nil when the estimates were missing or jumped around.
    public var tempo: Double?
    /// Coefficient of variation of the level (std dev / mean), clamped to 0...1: how much it breathes.
    public var dynamics: Double
    /// Seconds of real (non-silent) audio the summary rests on.
    public var seconds: TimeInterval

    public init(energy: Double, bassShare: Double, brightness: Double, tempo: Double?, dynamics: Double, seconds: TimeInterval) {
        self.energy = energy
        self.bassShare = bassShare
        self.brightness = brightness
        self.tempo = tempo
        self.dynamics = dynamics
        self.seconds = seconds
    }
}

/// Accumulates `AudioFeatures` while one track plays. Pure and clockless: every call passes `now`
/// (any monotonic seconds value). Time is counted between consecutive non-silent samples, and a gap
/// longer than `maxGap` (capture stalled, paused) counts for nothing, so "12 seconds heard" means
/// twelve seconds of actual sound.
public struct AudioProfile: Sendable {
    public var minSeconds: TimeInterval
    /// Samples with a level and energy at or below this are silence and are skipped.
    public var silenceLevel: Float
    public var maxGap: TimeInterval

    private var lastTime: TimeInterval?
    private var weight = 0.0                       // seconds heard
    private var sumEnergy = 0.0
    private var sumBass = 0.0
    private var sumBright = 0.0
    private var meanLevel = 0.0, m2Level = 0.0     // weighted Welford
    private var bpmWeights: [Int: Double] = [:]    // seconds per whole BPM
    private var bpmSeconds = 0.0

    public init(minSeconds: TimeInterval = 12, silenceLevel: Float = 0.03, maxGap: TimeInterval = 0.5) {
        self.minSeconds = minSeconds
        self.silenceLevel = silenceLevel
        self.maxGap = maxGap
    }

    /// Forget everything (call on every track change).
    public mutating func reset() {
        self = AudioProfile(minSeconds: minSeconds, silenceLevel: silenceLevel, maxGap: maxGap)
    }

    /// Seconds of non-silent audio seen so far.
    public var heardSeconds: TimeInterval { weight }

    public var isReady: Bool { weight >= minSeconds }

    public mutating func add(_ f: AudioFeatures, now: TimeInterval) {
        let silent = f.level <= silenceLevel && f.energy <= silenceLevel
        defer { lastTime = silent ? nil : now }
        guard !silent, let last = lastTime else { return }
        let dt = now - last
        guard dt > 0, dt <= maxGap else { return }

        weight += dt
        let total = Double(f.bass + f.mid + f.treble)
        sumEnergy += Double(f.energy) * dt
        sumBass += (total > 0 ? Double(f.bass) / total : 1.0 / 3.0) * dt
        sumBright += Double(f.brightness) * dt

        let x = Double(f.level)
        let delta = x - meanLevel
        meanLevel += delta * dt / weight
        m2Level += dt * delta * (x - meanLevel)

        if let bpm = f.bpm, bpm.isFinite, (Self.bpmRange).contains(bpm) {
            bpmWeights[Int(bpm.rounded()), default: 0] += dt
            bpmSeconds += dt
        }
    }

    /// Plausible tempo estimates; anything outside is a detector glitch.
    static let bpmRange: ClosedRange<Double> = 50...210

    /// nil until `isReady`.
    public var summary: AudioSummary? {
        guard isReady, weight > 0 else { return nil }
        let variance = max(0, m2Level / weight)
        let dynamics = meanLevel > 0.001 ? min(1, variance.squareRoot() / meanLevel) : 0
        return AudioSummary(energy: sumEnergy / weight, bassShare: sumBass / weight, brightness: sumBright / weight,
                            tempo: stableTempo, dynamics: dynamics, seconds: weight)
    }

    /// The tempo most of the estimates agree on. Estimates within 3 BPM of a center form one cluster;
    /// the best cluster must hold at least half of the estimate time, and there must be at least
    /// 3 seconds of estimates at all, otherwise the tempo is not trusted.
    var stableTempo: Double? {
        guard bpmSeconds >= 3 else { return nil }
        var best: (center: Int, weight: Double)?
        for center in bpmWeights.keys {
            let w = bpmWeights.reduce(0.0) { $0 + (abs($1.key - center) <= 3 ? $1.value : 0) }
            if best == nil || w > best!.weight || (w == best!.weight && center < best!.center) { best = (center, w) }
        }
        guard let b = best, b.weight >= 0.5 * bpmSeconds else { return nil }
        var sum = 0.0, wsum = 0.0
        for (k, w) in bpmWeights where abs(k - b.center) <= 3 { sum += Double(k) * w; wsum += w }
        return wsum > 0 ? sum / wsum : nil
    }
}
