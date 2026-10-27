import XCTest
@testable import LyraCore

private func feat(level: Float = 0.5, bass: Float = 0.5, mid: Float = 0.5, treble: Float = 0.5, bpm: Double? = nil,
                  brightness: Float = 0.5, energy: Float = 0.5) -> AudioFeatures {
    AudioFeatures(level: level, bass: bass, mid: mid, treble: treble, beat: 0, bpm: bpm, brightness: brightness, energy: energy)
}

private func summary(energy: Double = 0.45, bass: Double = 0.33, brightness: Double = 0.45, tempo: Double? = 100, dynamics: Double = 0.3) -> AudioSummary {
    AudioSummary(energy: energy, bassShare: bass, brightness: brightness, tempo: tempo, dynamics: dynamics, seconds: 20)
}

private func palette(_ dominant: RGBA, accent: RGBA, dark: Bool) -> Palette {
    Palette(dominant: dominant, accent: accent, secondary: accent, swatches: [dominant, accent], isDark: dark)
}

// MARK: - Mood

final class MoodTypeTests: XCTestCase {
    func testEveryMoodHasATitleAndSummary() {
        XCTAssertGreaterThanOrEqual(Mood.selectable.count, 12)
        for m in Mood.allCases {
            XCTAssertFalse(m.title.isEmpty)
            XCTAssertFalse(m.summary.isEmpty)
            XCTAssertFalse(m.summary.contains("\n"))
        }
        XCTAssertEqual(Set(Mood.allCases.map(\.title)).count, Mood.allCases.count)
        XCTAssertFalse(Mood.selectable.contains(.neutral))
    }

    func testRawValuesAreStableBecauseSettingsStoreThem() {
        XCTAssertEqual(Mood.melancholic.rawValue, "melancholic")
        XCTAssertEqual(Mood(rawValue: "energetic"), .energetic)
        XCTAssertNil(Mood(rawValue: "Energetic"))
    }
}

// MARK: - Audio profile

final class AudioProfileTests: XCTestCase {
    /// Feeds `seconds` of constant features at 20 Hz.
    private func feed(_ p: inout AudioProfile, _ f: AudioFeatures, seconds: Double, from start: Double = 0, hz: Double = 20) -> Double {
        var t = start
        let n = Int(seconds * hz)
        for _ in 0...n { p.add(f, now: t); t += 1 / hz }
        return t
    }

    func testNotReadyBeforeTheMinimumAndReadyAfter() {
        var p = AudioProfile()
        _ = feed(&p, feat(), seconds: 8)
        XCTAssertFalse(p.isReady)
        XCTAssertNil(p.summary)
        XCTAssertEqual(p.heardSeconds, 8, accuracy: 0.1)
        _ = feed(&p, feat(), seconds: 6, from: 8.05)
        XCTAssertTrue(p.isReady)
        XCTAssertNotNil(p.summary)
    }

    func testCustomMinimum() {
        var p = AudioProfile(minSeconds: 3)
        _ = feed(&p, feat(), seconds: 3.5)
        XCTAssertTrue(p.isReady)
    }

    func testSilenceIsIgnoredAndDoesNotCountAsTime() {
        var p = AudioProfile(minSeconds: 5)
        var t = feed(&p, feat(), seconds: 3)
        t = feed(&p, AudioFeatures.silent, seconds: 30, from: t)
        XCTAssertEqual(p.heardSeconds, 3, accuracy: 0.1)
        XCTAssertFalse(p.isReady)
        // Sound resumes: the first sample after silence has no predecessor, so it adds no time.
        t = feed(&p, feat(), seconds: 2.5, from: t)
        XCTAssertEqual(p.heardSeconds, 5.4, accuracy: 0.15)
        XCTAssertTrue(p.isReady)
    }

    func testSilenceDoesNotSkewTheAverages() throws {
        var p = AudioProfile(minSeconds: 4)
        var t = feed(&p, feat(brightness: 0.8, energy: 0.7), seconds: 5)
        t = feed(&p, AudioFeatures.silent, seconds: 20, from: t)
        let s = try XCTUnwrap(p.summary)
        XCTAssertEqual(s.brightness, 0.8, accuracy: 0.001)
        XCTAssertEqual(s.energy, 0.7, accuracy: 0.001)
    }

    func testLargeGapsCountForNothing() {
        var p = AudioProfile(minSeconds: 1)
        p.add(feat(), now: 0)
        p.add(feat(), now: 10)       // capture stalled for 10 s
        XCTAssertEqual(p.heardSeconds, 0)
        p.add(feat(), now: 10.1)
        XCTAssertEqual(p.heardSeconds, 0.1, accuracy: 1e-9)
        p.add(feat(), now: 10.1)     // same instant
        p.add(feat(), now: 5)        // time going backwards
        XCTAssertEqual(p.heardSeconds, 0.1, accuracy: 1e-9)
    }

    func testMeansAndBassShare() throws {
        var p = AudioProfile(minSeconds: 5)
        _ = feed(&p, feat(bass: 0.8, mid: 0.4, treble: 0.2, brightness: 0.3, energy: 0.6), seconds: 6)
        let s = try XCTUnwrap(p.summary)
        XCTAssertEqual(s.energy, 0.6, accuracy: 1e-6)
        XCTAssertEqual(s.brightness, 0.3, accuracy: 1e-6)
        XCTAssertEqual(s.bassShare, 0.8 / 1.4, accuracy: 1e-6)
        XCTAssertEqual(s.seconds, 6, accuracy: 0.1)
    }

    func testDynamicsIsZeroForAConstantLevelAndLargeForAPulsingOne() throws {
        var steady = AudioProfile(minSeconds: 5)
        _ = feed(&steady, feat(level: 0.5), seconds: 6)
        XCTAssertEqual(try XCTUnwrap(steady.summary).dynamics, 0, accuracy: 1e-6)

        var pulsing = AudioProfile(minSeconds: 5)
        var t = 0.0
        for i in 0...120 { pulsing.add(feat(level: i % 2 == 0 ? 0.9 : 0.1), now: t); t += 0.05 }
        // mean 0.5, std 0.4 -> 0.8
        XCTAssertEqual(try XCTUnwrap(pulsing.summary).dynamics, 0.8, accuracy: 0.03)
    }

    func testDynamicsMathMatchesAHandComputedWeightedVariance() throws {
        var p = AudioProfile(minSeconds: 1)
        // levels 0.2, 0.4, 0.6 each for 0.1 s of weight (first sample carries no weight).
        for (i, l) in [Float(0.9), 0.2, 0.4, 0.6].enumerated() { p.add(feat(level: l), now: Double(i) * 0.1) }
        p.minSeconds = 0.25
        let s = try XCTUnwrap(p.summary)
        let mean = 0.4, variance = ((0.2 * 0.2) + 0 + (0.2 * 0.2)) / 3
        XCTAssertEqual(s.dynamics, variance.squareRoot() / mean, accuracy: 1e-4)
    }

    func testStableTempoIgnoresNilGlitchesAndOutliers() throws {
        var p = AudioProfile(minSeconds: 5)
        var t = 0.0
        for i in 0..<200 {
            let bpm: Double? = i % 10 == 0 ? nil : (i % 17 == 0 ? 500 : 120 + Double(i % 3) - 1)   // 119, 120, 121, some nil, some absurd
            p.add(feat(bpm: bpm), now: t); t += 0.05
        }
        XCTAssertEqual(try XCTUnwrap(p.summary?.tempo), 120, accuracy: 1.5)
    }

    func testUnstableTempoIsNil() throws {
        var p = AudioProfile(minSeconds: 5)
        var t = 0.0
        let spread: [Double] = [70, 90, 110, 130, 150, 170, 190]
        for i in 0..<200 { p.add(feat(bpm: spread[i % spread.count]), now: t); t += 0.05 }
        XCTAssertNil(try XCTUnwrap(p.summary).tempo)
    }

    func testTempoNeedsEnoughEstimatesAndNoneMeansNil() throws {
        var none = AudioProfile(minSeconds: 5)
        _ = feed(&none, feat(bpm: nil), seconds: 6)
        XCTAssertNil(try XCTUnwrap(none.summary).tempo)
        var brief = AudioProfile(minSeconds: 5)
        var t = feed(&brief, feat(bpm: nil), seconds: 5)
        t = feed(&brief, feat(bpm: 100), seconds: 1.5, from: t)   // under 3 s of estimates
        XCTAssertNil(try XCTUnwrap(brief.summary).tempo)
    }

    func testResetStartsOver() {
        var p = AudioProfile(minSeconds: 2)
        _ = feed(&p, feat(), seconds: 3)
        XCTAssertTrue(p.isReady)
        p.reset()
        XCTAssertFalse(p.isReady)
        XCTAssertEqual(p.heardSeconds, 0)
        XCTAssertEqual(p.minSeconds, 2, "settings survive a reset")
        XCTAssertNil(p.summary)
    }
}

// MARK: - Mood engine

final class MoodEngineTests: XCTestCase {
    let engine = MoodEngine()

    func testNoSignalsAtAllIsNeutralWithZeroConfidence() {
        let g = engine.guess()
        XCTAssertEqual(g.mood, .neutral)
        XCTAssertEqual(g.confidence, 0)
        XCTAssertFalse(g.reasons.isEmpty)
    }

    func testAnUnknownGenreCountsAsNoSignal() {
        XCTAssertEqual(engine.guess(genre: "Qwertyuiop").mood, .neutral)
        XCTAssertEqual(engine.guess(genre: "").mood, .neutral)
        XCTAssertEqual(engine.guess(genre: "Music", audio: nil, palette: nil).confidence, 0)
    }

    func testGenreAloneKeepsItsOwnConfidence() throws {
        let g = engine.guess(genre: "Heavy Metal")
        XCTAssertEqual(g.mood, .aggressive)
        XCTAssertEqual(g.confidence, try XCTUnwrap(GenreClassifier.classify("Heavy Metal")).confidence, accuracy: 1e-9)
        XCTAssertTrue(g.reasons[0].contains("Heavy Metal"))
    }

    func testAudioAloneCanDecide() {
        let fast = engine.guess(audio: summary(energy: 0.75, bass: 0.34, brightness: 0.7, tempo: 150, dynamics: 0.3))
        XCTAssertEqual(fast.mood, .energetic)
        XCTAssertGreaterThan(fast.confidence, 0.4)
        let sad = engine.guess(audio: summary(energy: 0.15, bass: 0.3, brightness: 0.15, tempo: 62, dynamics: 0.1))
        XCTAssertEqual(sad.mood, .melancholic)
    }

    func testAudioRulesForTheDocumentedProfiles() {
        // fast and loud and bright
        XCTAssertTrue([.energetic, .party].contains(engine.guess(audio: summary(energy: 0.8, bass: 0.36, brightness: 0.72, tempo: 128)).mood))
        // slow, quiet, dark
        XCTAssertTrue([.melancholic, .dark].contains(engine.guess(audio: summary(energy: 0.18, bass: 0.34, brightness: 0.18, tempo: 60)).mood))
        // slow, quiet, steady, bright
        XCTAssertTrue([.dreamy, .chill].contains(engine.guess(audio: summary(energy: 0.2, bass: 0.3, brightness: 0.7, tempo: 66, dynamics: 0.1)).mood))
        // heavy bass, low brightness, loud
        XCTAssertTrue([.aggressive, .dark].contains(engine.guess(audio: summary(energy: 0.8, bass: 0.6, brightness: 0.15, tempo: 140, dynamics: 0.3)).mood))
        // heavy bass, low brightness, quiet
        XCTAssertEqual(engine.guess(audio: summary(energy: 0.2, bass: 0.6, brightness: 0.15, tempo: 80, dynamics: 0.2)).mood, .dark)
        // quiet and dynamic, little bass
        XCTAssertEqual(engine.guess(audio: summary(energy: 0.18, bass: 0.28, brightness: 0.5, tempo: 95, dynamics: 0.8)).mood, .acoustic)
        // dance tempo, loud, bassy
        XCTAssertEqual(engine.guess(audio: summary(energy: 0.75, bass: 0.5, brightness: 0.5, tempo: 124, dynamics: 0.25)).mood, .party)
    }

    func testAudioWithoutTempoStillWorksButIsWeaker() {
        let withTempo = engine.guess(audio: summary(energy: 0.75, brightness: 0.7, tempo: 150))
        let without = engine.guess(audio: summary(energy: 0.75, brightness: 0.7, tempo: nil))
        XCTAssertLessThan(without.confidence, withTempo.confidence)
    }

    func testCoverAloneLeansButNeverClaimsMuch() {
        let dark = engine.guess(palette: palette(RGBA(0.05, 0.05, 0.07), accent: RGBA(0.3, 0.3, 0.35), dark: true))
        XCTAssertTrue([.dark, .melancholic].contains(dark.mood), "\(dark)")
        let warm = engine.guess(palette: palette(RGBA(0.95, 0.6, 0.2), accent: RGBA(1, 0.65, 0.1), dark: false))
        XCTAssertEqual(warm.mood, .playful)
        let pink = engine.guess(palette: palette(RGBA(0.9, 0.3, 0.45), accent: RGBA(1, 0.2, 0.4), dark: false))
        XCTAssertEqual(pink.mood, .romantic)
        let cool = engine.guess(palette: palette(RGBA(0.2, 0.5, 0.8), accent: RGBA(0.1, 0.6, 0.95), dark: false))
        XCTAssertEqual(cool.mood, .chill)
        let violet = engine.guess(palette: palette(RGBA(0.35, 0.2, 0.7), accent: RGBA(0.6, 0.3, 1), dark: true))
        XCTAssertTrue([.dreamy, .dark, .chill].contains(violet.mood), "\(violet)")
        let green = engine.guess(palette: palette(RGBA(0.3, 0.6, 0.3), accent: RGBA(0.25, 0.8, 0.3), dark: false))
        XCTAssertEqual(green.mood, .acoustic)
        for g in [dark, warm, pink, cool, green] { XCTAssertLessThanOrEqual(g.confidence, 0.6, "the cover alone is weak evidence") }
    }

    func testAGreyCoverSaysNothingSpecific() {
        let grey = palette(RGBA(0.6, 0.6, 0.6), accent: RGBA(0.62, 0.62, 0.62), dark: false)
        XCTAssertLessThan(engine.guess(palette: grey).confidence, 0.35)
    }

    func testGenreOutweighsAudioWhichOutweighsCover() {
        let calmAudio = summary(energy: 0.15, bass: 0.3, brightness: 0.15, tempo: 62, dynamics: 0.1)
        let cheerfulCover = palette(RGBA(0.95, 0.6, 0.2), accent: RGBA(1, 0.65, 0.1), dark: false)
        // confident genre vs contradicting audio and cover: genre wins
        XCTAssertEqual(engine.guess(genre: "Heavy Metal", audio: calmAudio, palette: cheerfulCover).mood, .aggressive)
        // weak genre (generic "Pop") vs strong contradicting audio: audio wins
        XCTAssertEqual(engine.guess(genre: "Pop", audio: calmAudio).mood, .melancholic)
        // audio vs cover with no genre: audio wins
        XCTAssertEqual(engine.guess(audio: calmAudio, palette: cheerfulCover).mood, .melancholic)
    }

    func testAgreementRaisesConfidenceAndDisagreementLowersIt() {
        let fast = summary(energy: 0.75, bass: 0.34, brightness: 0.7, tempo: 150)
        let alone = engine.guess(genre: "Rock").confidence
        let agree = engine.guess(genre: "Rock", audio: fast)
        let disagree = engine.guess(genre: "Rock", audio: summary(energy: 0.15, bass: 0.3, brightness: 0.15, tempo: 62, dynamics: 0.1))
        XCTAssertEqual(agree.mood, .energetic)
        XCTAssertGreaterThan(agree.confidence, alone)
        XCTAssertEqual(disagree.mood, .energetic)
        XCTAssertLessThan(disagree.confidence, alone)
    }

    func testAnySubsetOfSignalsWorks() {
        let a = summary(energy: 0.75, brightness: 0.7, tempo: 150)
        let p = palette(RGBA(0.2, 0.5, 0.8), accent: RGBA(0.1, 0.6, 0.95), dark: false)
        for genre in [nil, "Rock"] as [String?] {
            for audio in [nil, a] as [AudioSummary?] {
                for cover in [nil, p] as [Palette?] {
                    let g = engine.guess(genre: genre, audio: audio, palette: cover)
                    XCTAssertTrue((0...1).contains(g.confidence))
                    if genre == nil && audio == nil && cover == nil { XCTAssertEqual(g.mood, .neutral) }
                    else { XCTAssertFalse(g.reasons.isEmpty) }
                }
            }
        }
    }

    func testReasonsNameEachSourceUsed() {
        let g = engine.guess(genre: "Rock", audio: summary(energy: 0.75, brightness: 0.7, tempo: 150),
                             palette: palette(RGBA(0.05, 0.05, 0.07), accent: RGBA(0.3, 0.3, 0.35), dark: true))
        XCTAssertEqual(g.reasons.count, 3)
        XCTAssertTrue(g.reasons[0].hasPrefix("genre"))
        XCTAssertTrue(g.reasons[1].hasPrefix("audio"))
        XCTAssertTrue(g.reasons[2].hasPrefix("cover"))
        XCTAssertTrue(g.reasons[1].contains("150 BPM"))
    }

    func testCustomWeightsChangeTheOutcome() {
        var e = MoodEngine()
        e.weights.genre = 0.05
        e.weights.audio = 0.9
        let calm = summary(energy: 0.15, bass: 0.3, brightness: 0.15, tempo: 62, dynamics: 0.1)
        XCTAssertEqual(e.guess(genre: "Heavy Metal", audio: calm).mood, .melancholic)
    }

    func testHSV() {
        XCTAssertEqual(MoodEngine.hsv(RGBA(1, 0, 0)).h, 0, accuracy: 0.01)
        XCTAssertEqual(MoodEngine.hsv(RGBA(0, 1, 0)).h, 120, accuracy: 0.01)
        XCTAssertEqual(MoodEngine.hsv(RGBA(0, 0, 1)).h, 240, accuracy: 0.01)
        XCTAssertEqual(MoodEngine.hsv(RGBA(0.5, 0.5, 0.5)).s, 0, accuracy: 1e-9)
        XCTAssertEqual(MoodEngine.hsv(RGBA(1, 0, 0.5)).h, 330, accuracy: 0.01)
    }
}
