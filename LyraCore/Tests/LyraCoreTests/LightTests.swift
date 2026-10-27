import XCTest
@testable import LyraCore

private func features(beat: Float = 0, bass: Float = 0, level: Float = 0) -> AudioFeatures {
    AudioFeatures(level: level, bass: bass, mid: 0, treble: 0, beat: beat, bpm: nil, brightness: 0, energy: 0)
}

final class RimGlowEffectTests: XCTestCase {
    private let effect = RimGlowEffect()
    private let blue = RGBA(0, 0, 1), pink = RGBA(1, 0, 1)

    private func params(_ f: AudioFeatures?, config: LightConfig = LightConfig(), time: Double = 0) -> LightParams? {
        effect.params(LightInput(features: f, primary: blue, secondary: pink, time: time), config: config)
    }

    func testDisabledDrawsNothing() {
        var c = LightConfig()
        c.enabled = false
        XCTAssertNil(params(features(beat: 1), config: c))
    }

    func testBeatMakesItBrighterAndThicker() throws {
        let quiet = try XCTUnwrap(params(features()))
        let hit = try XCTUnwrap(params(features(beat: 1)))
        XCTAssertGreaterThan(hit.intensity, quiet.intensity + 0.2)
        XCTAssertGreaterThan(hit.thickness, quiet.thickness)
    }

    func testIdleGlowIsTheFloor() throws {
        var c = LightConfig()
        c.idleGlow = 0.3
        c.intensity = 1
        XCTAssertEqual(try XCTUnwrap(params(features(), config: c)).intensity, 0.3, accuracy: 0.001)
    }

    func testReactivityZeroIgnoresTheMusic() throws {
        var c = LightConfig()
        c.beatReactivity = 0
        let loud = try XCTUnwrap(params(features(beat: 1, bass: 1, level: 1), config: c))
        let quiet = try XCTUnwrap(params(features(), config: c))
        XCTAssertEqual(loud.intensity, quiet.intensity, accuracy: 1e-6)
        XCTAssertEqual(loud.thickness, quiet.thickness, accuracy: 1e-9)
    }

    func testIntensityIsClampedAndScaledByTheConfig() throws {
        let max = try XCTUnwrap(params(features(beat: 1, bass: 1, level: 1)))
        XCTAssertLessThanOrEqual(max.intensity, 1)
        var dim = LightConfig()
        dim.intensity = 0.2
        let dimmed = try XCTUnwrap(params(features(beat: 1, bass: 1, level: 1), config: dim))
        XCTAssertLessThan(dimmed.intensity, max.intensity)
    }

    func testWithoutAudioItBreathesSlowly() throws {
        let values = try (0..<50).map { try XCTUnwrap(params(nil, time: Double($0) * 0.1)).intensity }
        XCTAssertGreaterThan(values.max()! - values.min()!, 0.05, "breathing visibly varies")
        XCTAssertGreaterThan(values.min()!, 0, "never fully dark while enabled")
    }

    func testManualColorsOverrideTheInput() throws {
        var c = LightConfig()
        c.primary = RGBA(1, 0, 0)
        let p = try XCTUnwrap(params(features(), config: c))
        XCTAssertEqual(p.primary, RGBA(1, 0, 0))
        XCTAssertEqual(p.secondary, pink, "unset manual color falls back to the input")
    }

    func testPhaseDriftsAndWraps() throws {
        var c = LightConfig()
        c.driftSpeed = 0.25
        XCTAssertEqual(try XCTUnwrap(params(features(), config: c, time: 2)).phase, 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(params(features(), config: c, time: 4)).phase, 0, accuracy: 1e-9)
    }
}

final class TolerantDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testEmptyObjectGivesDefaults() throws {
        XCTAssertEqual(try decode(OverlayConfig.self, "{}"), OverlayConfig())
        XCTAssertEqual(try decode(LightConfig.self, "{}"), LightConfig())
    }

    func testPartialFileKeepsOtherDefaults() throws {
        let c = try decode(OverlayConfig.self, #"{"glow": 0.1, "latencyOffset": 0.4}"#)
        XCTAssertEqual(c.glow, 0.1, accuracy: 1e-6)
        XCTAssertEqual(c.latencyOffset, 0.4, accuracy: 1e-9)
        XCTAssertEqual(c.font, OverlayConfig().font)
        XCTAssertEqual(c.secondaryScale, OverlayConfig().secondaryScale)
    }

    func testMalformedValueFallsBackInsteadOfFailing() throws {
        let c = try decode(LightConfig.self, #"{"thickness": "wide", "intensity": 0.4}"#)
        XCTAssertEqual(c.thickness, LightConfig().thickness)
        XCTAssertEqual(c.intensity, 0.4, accuracy: 1e-6)
    }

    func testRoundTrip() throws {
        var o = OverlayConfig()
        o.font = FontSpec(family: "Helvetica Neue", size: 60, weight: 0.2)
        o.glowColor = RGBA(1, 0.2, 0.3, 0.9)
        var l = LightConfig()
        l.primary = RGBA(0.1, 0.2, 0.3)
        l.thickness = 40
        XCTAssertEqual(try decode(OverlayConfig.self, String(decoding: JSONEncoder().encode(o), as: UTF8.self)), o)
        XCTAssertEqual(try decode(LightConfig.self, String(decoding: JSONEncoder().encode(l), as: UTF8.self)), l)
    }
}
