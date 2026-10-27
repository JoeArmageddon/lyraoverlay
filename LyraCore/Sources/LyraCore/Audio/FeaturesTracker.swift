import Foundation

/// A snapshot of how the music sounds right now, all values 0...1 unless noted.
public struct AudioFeatures: Equatable, Sendable {
    /// Smoothed loudness.
    public var level: Float
    public var bass: Float
    public var mid: Float
    public var treble: Float
    /// 1 at a detected beat, decaying toward 0 in about 0.2 s.
    public var beat: Float
    /// nil until enough beats have been heard.
    public var bpm: Double?
    /// Spectral brightness: 0 dark and bassy, 1 bright and airy.
    public var brightness: Float
    /// Slow average of the level over several seconds: how intense the song is overall.
    public var energy: Float

    public init(level: Float, bass: Float, mid: Float, treble: Float, beat: Float, bpm: Double?, brightness: Float, energy: Float) {
        self.level = level
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.beat = beat
        self.bpm = bpm
        self.brightness = brightness
        self.energy = energy
    }

    public static let silent = AudioFeatures(level: 0, bass: 0, mid: 0, treble: 0, beat: 0, bpm: nil, brightness: 0, energy: 0)
}

/// Turns raw audio into `AudioFeatures`. `ingest` runs on the capture queue and
/// `features(at:)` on the render thread; a lock makes both safe.
public final class FeaturesTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var analyzer: SpectrumAnalyzer
    private var detector = BeatDetector()

    private var level: Float = 0, bass: Float = 0, mid: Float = 0, treble: Float = 0
    private var brightness: Float = 0, energy: Float = 0
    private var peaks: (bass: Float, mid: Float, treble: Float, level: Float) = (0.02, 0.02, 0.01, 0.05)
    private var lastBeat: Date?
    private var lastIngest: Date?
    private var _beatCount = 0

    /// Beats detected since the last reset. For diagnostics and tests.
    public var beatCount: Int { lock.withLock { _beatCount } }

    public init(sampleRate: Double = 48_000) {
        analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
    }

    /// `at` is when these samples ended, normally now.
    public func ingest(_ samples: [Float], at date: Date = Date()) {
        lock.withLock {
            let frames = analyzer.process(samples)
            guard let newest = frames.last else { return }
            lastIngest = date
            for frame in frames {
                update(with: frame)
                if let beatTime = detector.process(frame) {
                    // Map the beat's audio time back to the wall clock.
                    lastBeat = date.addingTimeInterval(beatTime - newest.time)
                    _beatCount += 1
                }
            }
        }
    }

    public func features(at date: Date = Date()) -> AudioFeatures {
        lock.withLock {
            // No audio for a moment (paused, or capture stalled): fade out instead of freezing.
            let idle = lastIngest.map { date.timeIntervalSince($0) } ?? .infinity
            let fade = Float(max(0, 1 - max(0, idle - 0.3) / 0.7))
            var beat: Float = 0
            if let lastBeat { beat = Float(exp(-max(0, date.timeIntervalSince(lastBeat)) / 0.2)) }
            return AudioFeatures(
                level: level * fade, bass: bass * fade, mid: mid * fade, treble: treble * fade,
                beat: beat * fade, bpm: detector.bpm, brightness: brightness, energy: energy * fade)
        }
    }

    /// The sample rate the analyzer currently assumes.
    public var sampleRate: Double { lock.withLock { analyzer.sampleRate } }

    /// Switches to a different input sample rate (the tap reports the real one only after it
    /// starts). Clears all state; does nothing when the rate is unchanged.
    public func reconfigure(sampleRate: Double) {
        lock.withLock {
            guard sampleRate > 0, analyzer.sampleRate != sampleRate else { return }
            analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
        }
        reset()
    }

    public func reset() {
        lock.withLock {
            analyzer.reset()
            detector.reset()
            level = 0; bass = 0; mid = 0; treble = 0; brightness = 0; energy = 0
            peaks = (0.02, 0.02, 0.01, 0.05)
            lastBeat = nil
            lastIngest = nil
            _beatCount = 0
        }
    }

    // MARK: - Smoothing

    /// Fast attack and slower release per ~10 ms frame, with each band scaled by its own
    /// slowly decaying peak so quiet songs and loud songs both fill the 0...1 range.
    private func update(with f: SpectralFrame) {
        peaks.bass = max(f.bass, peaks.bass * 0.9995, 0.005)
        peaks.mid = max(f.mid, peaks.mid * 0.9995, 0.005)
        peaks.treble = max(f.treble, peaks.treble * 0.9995, 0.003)
        peaks.level = max(f.rms, peaks.level * 0.9995, 0.01)

        level = ease(level, min(1, f.rms / peaks.level), up: 0.5, down: 0.06)
        bass = ease(bass, min(1, f.bass / peaks.bass), up: 0.6, down: 0.08)
        mid = ease(mid, min(1, f.mid / peaks.mid), up: 0.5, down: 0.07)
        treble = ease(treble, min(1, f.treble / peaks.treble), up: 0.5, down: 0.09)
        brightness = ease(brightness, f.centroid, up: 0.02, down: 0.02)
        energy = ease(energy, level, up: 0.002, down: 0.002)   // about an 8 s time constant
    }

    private func ease(_ current: Float, _ target: Float, up: Float, down: Float) -> Float {
        current + (target - current) * (target > current ? up : down)
    }
}
