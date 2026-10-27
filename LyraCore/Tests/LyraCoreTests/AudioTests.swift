import XCTest
@testable import LyraCore

private let sr = 48_000.0

private func sine(_ hz: Double, amplitude: Float = 0.5, seconds: Double) -> [Float] {
    (0..<Int(seconds * sr)).map { amplitude * Float(sin(2 * Double.pi * hz * Double($0) / sr)) }
}

/// A short low-frequency thump with a bit of noise on every beat, on a silent background.
private func clickTrack(bpm: Double, seconds: Double) -> [Float] {
    var out = [Float](repeating: 0, count: Int(seconds * sr))
    let interval = 60 / bpm
    var seed: UInt32 = 12345
    var t = 0.1
    while t < seconds {
        let start = Int(t * sr)
        for i in 0..<Int(0.04 * sr) where start + i < out.count {
            let envelope = Float(exp(-Double(i) / (0.008 * sr)))
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Float(seed >> 8) / Float(1 << 24) * 2 - 1
            out[start + i] += envelope * (0.6 * Float(sin(2 * Double.pi * 80 * Double(i) / sr)) + 0.3 * noise)
        }
        t += interval
    }
    return out
}

private func detect(_ samples: [Float]) -> (beats: [Double], bpm: Double?) {
    let analyzer = SpectrumAnalyzer(sampleRate: sr)
    var detector = BeatDetector()
    var beats: [Double] = []
    for frame in analyzer.process(samples) {
        if let t = detector.process(frame) { beats.append(t) }
    }
    return (beats, detector.bpm)
}

final class SpectrumAnalyzerTests: XCTestCase {
    func testLowSineLandsInTheBassBand() {
        let frames = SpectrumAnalyzer(sampleRate: sr).process(sine(100, seconds: 1))
        let f = frames[frames.count / 2]
        XCTAssertEqual(f.bass, 0.5, accuracy: 0.15, "magnitudes are in sine-amplitude units")
        XCTAssertLessThan(f.mid, 0.05)
        XCTAssertLessThan(f.treble, 0.05)
    }

    func testHighSineLandsInTheTrebleBand() {
        let frames = SpectrumAnalyzer(sampleRate: sr).process(sine(8_000, seconds: 1))
        let f = frames[frames.count / 2]
        XCTAssertGreaterThan(f.treble, 0.3)
        XCTAssertLessThan(f.bass, 0.05)
        XCTAssertGreaterThan(f.centroid, 0.7)
    }

    func testCentroidRisesWithPitch() {
        func centroid(_ hz: Double) -> Float {
            let frames = SpectrumAnalyzer(sampleRate: sr).process(sine(hz, seconds: 0.5))
            return frames[frames.count / 2].centroid
        }
        XCTAssertLessThan(centroid(100), centroid(1_000))
        XCTAssertLessThan(centroid(1_000), centroid(6_000))
    }

    func testFrameTimesAdvanceByTheHop() {
        let frames = SpectrumAnalyzer(sampleRate: sr).process(sine(440, seconds: 0.5))
        XCTAssertGreaterThan(frames.count, 20)
        XCTAssertEqual(frames[1].time - frames[0].time, 512 / sr, accuracy: 1e-9)
    }

    func testChunkedInputMatchesOneShot() {
        let signal = sine(220, seconds: 0.6)
        let oneShot = SpectrumAnalyzer(sampleRate: sr).process(signal)
        let chunked = SpectrumAnalyzer(sampleRate: sr)
        var frames: [SpectralFrame] = []
        var i = 0
        while i < signal.count {
            frames += chunked.process(Array(signal[i..<min(i + 480, signal.count)]))
            i += 480
        }
        XCTAssertEqual(frames.count, oneShot.count)
        XCTAssertEqual(frames.last?.bass ?? 0, oneShot.last?.bass ?? -1, accuracy: 1e-4)
    }

    func testSilenceIsSilent() {
        let frames = SpectrumAnalyzer(sampleRate: sr).process([Float](repeating: 0, count: 8_000))
        XCTAssertTrue(frames.allSatisfy { $0.rms == 0 && $0.bass == 0 && $0.flux == 0 })
    }
}

final class BeatDetectorTests: XCTestCase {
    func testFindsBeatsAndTempoOfA120BPMTrack() {
        let (beats, bpm) = detect(clickTrack(bpm: 120, seconds: 14))
        XCTAssertTrue((22...30).contains(beats.count), "expected about 27 beats, got \(beats.count)")
        XCTAssertEqual(bpm ?? 0, 120, accuracy: 3)
    }

    func testFindsTempoOfA90BPMTrack() {
        let (_, bpm) = detect(clickTrack(bpm: 90, seconds: 16))
        XCTAssertEqual(bpm ?? 0, 90, accuracy: 3)
    }

    func testBeatTimesLandOnTheGrid() {
        let (beats, _) = detect(clickTrack(bpm: 120, seconds: 10))
        // Clicks start at 0.1 s and repeat every 0.5 s; allow for window latency (about 45 ms).
        for t in beats.dropFirst(2) {
            let phase = (t - 0.1).truncatingRemainder(dividingBy: 0.5)
            let off = min(phase, 0.5 - phase)
            XCTAssertLessThan(off, 0.09, "beat at \(t)s is off the grid by \(off)s")
        }
    }

    func testSilenceHasNoBeatsOrTempo() {
        let (beats, bpm) = detect([Float](repeating: 0, count: Int(5 * sr)))
        XCTAssertTrue(beats.isEmpty)
        XCTAssertNil(bpm)
    }

    func testSteadyToneHasNoBeats() {
        let (beats, bpm) = detect(sine(200, seconds: 6))
        XCTAssertLessThanOrEqual(beats.count, 1)
        XCTAssertNil(bpm)
    }

    func testNoTwoBeatsCloserThanTheMinimumInterval() {
        let (beats, _) = detect(clickTrack(bpm: 170, seconds: 10))
        for (a, b) in zip(beats, beats.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, BeatDetector.minInterval - 1e-9) }
    }
}

final class FeaturesTrackerTests: XCTestCase {
    /// Feeds audio in 10 ms chunks with a simulated clock; returns the clock at the end.
    private func feed(_ tracker: FeaturesTracker, _ samples: [Float], from start: Date) -> Date {
        var date = start
        var i = 0
        let chunk = 480
        while i < samples.count {
            let end = min(i + chunk, samples.count)
            date = date.addingTimeInterval(Double(end - i) / sr)
            tracker.ingest(Array(samples[i..<end]), at: date)
            i = end
        }
        return date
    }

    func testBeatPulseSpikesThenDecays() {
        let tracker = FeaturesTracker(sampleRate: sr)
        let end = feed(tracker, clickTrack(bpm: 120, seconds: 8), from: Date(timeIntervalSince1970: 1_000))
        // The last click ended a moment before the clock; a beat was confirmed recently.
        let soon = tracker.features(at: end.addingTimeInterval(-0.3))
        XCTAssertGreaterThan(soon.beat, 0.1)
        XCTAssertEqual(tracker.features(at: end).bpm ?? 0, 120, accuracy: 4)
    }

    func testBeatDecaysToNothing() {
        let tracker = FeaturesTracker(sampleRate: sr)
        let end = feed(tracker, clickTrack(bpm: 120, seconds: 6), from: Date(timeIntervalSince1970: 1_000))
        XCTAssertLessThan(tracker.features(at: end.addingTimeInterval(5)).beat, 0.01)
    }

    func testFadesToSilenceWhenAudioStops() {
        let tracker = FeaturesTracker(sampleRate: sr)
        let end = feed(tracker, sine(100, seconds: 3), from: Date(timeIntervalSince1970: 1_000))
        XCTAssertGreaterThan(tracker.features(at: end).bass, 0.5)
        let later = tracker.features(at: end.addingTimeInterval(2))
        XCTAssertEqual(later.bass, 0)
        XCTAssertEqual(later.level, 0)
    }

    func testAutoGainMakesQuietAndLoudSongsSimilar() {
        func settledBass(amplitude: Float) -> Float {
            let tracker = FeaturesTracker(sampleRate: sr)
            let end = feed(tracker, sine(100, amplitude: amplitude, seconds: 4), from: Date(timeIntervalSince1970: 1_000))
            return tracker.features(at: end).bass
        }
        XCTAssertGreaterThan(settledBass(amplitude: 0.04), 0.7)
        XCTAssertGreaterThan(settledBass(amplitude: 0.8), 0.7)
    }

    func testBassSineReadsBassNotTreble() {
        let tracker = FeaturesTracker(sampleRate: sr)
        let end = feed(tracker, sine(80, seconds: 3), from: Date(timeIntervalSince1970: 1_000))
        let f = tracker.features(at: end)
        XCTAssertGreaterThan(f.bass, 0.7)
        XCTAssertLessThan(f.treble, f.bass)
        XCTAssertLessThan(f.brightness, 0.4)
    }

    func testResetClearsEverything() {
        let tracker = FeaturesTracker(sampleRate: sr)
        let end = feed(tracker, clickTrack(bpm: 120, seconds: 6), from: Date(timeIntervalSince1970: 1_000))
        tracker.reset()
        XCTAssertEqual(tracker.features(at: end), .silent)
    }
}
