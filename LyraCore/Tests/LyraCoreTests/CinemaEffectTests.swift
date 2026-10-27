import XCTest
import CoreGraphics
@testable import LyraCore

final class CinemaPictureRectTests: XCTestCase {
    private func settings(_ ratio: LetterboxRatio, enabled: Bool = true) -> CinemaSettings {
        var s = CinemaSettings()
        s.enabled = enabled
        s.letterbox = ratio
        return s
    }

    func testEachRatioFitsCenteredInATallerWindow() {
        let view = CGSize(width: 1200, height: 800)   // 1.5:1, taller than every ratio
        for ratio in [LetterboxRatio.cinemascope, .flat, .wide] {
            let rect = CinemaEffect.pictureRect(settings: settings(ratio), viewport: view)
            let aspect = ratio.aspect!
            XCTAssertEqual(rect.width, 1200, accuracy: 1e-9, "\(ratio): full width, never pillarboxed")
            XCTAssertEqual(rect.width / rect.height, CGFloat(aspect), accuracy: 1e-9, "\(ratio): exact aspect")
            XCTAssertEqual(rect.midY, view.height / 2, accuracy: 1e-9, "\(ratio): centered vertically")
            XCTAssertGreaterThan(rect.minY, 0)
        }
    }

    func testBarsAndPictureAddUpToTheWholeHeight() {
        for view in [CGSize(width: 1000, height: 1000), CGSize(width: 1512, height: 982), CGSize(width: 480, height: 300), CGSize(width: 300, height: 900)] {
            let rect = CinemaEffect.pictureRect(settings: settings(.cinemascope), viewport: view)
            let frame = CinemaEffect.frame(settings: settings(.cinemascope), viewport: view, beat: 0, bass: 0, emphasisCenter: nil, time: 0)!
            let bar = CGFloat(frame.barFraction) * view.height
            XCTAssertEqual(bar * 2 + rect.height, view.height, accuracy: 1e-6, "\(view)")
            XCTAssertEqual(frame.pictureRect(in: view).height, rect.height, accuracy: 1e-6)
            XCTAssertEqual(frame.pictureRect(in: view).minY, rect.minY, accuracy: 1e-6)
        }
    }

    func testAWindowWiderThanTheRatioGetsNoBars() {
        let wide = CGSize(width: 2000, height: 700)   // 2.86:1, wider than 2.39
        let rect = CinemaEffect.pictureRect(settings: settings(.cinemascope), viewport: wide)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: wide), "never pillarbox")
        let frame = CinemaEffect.frame(settings: settings(.cinemascope), viewport: wide, beat: 0, bass: 0, emphasisCenter: nil, time: 0)!
        XCTAssertEqual(frame.barFraction, 0)
    }

    func testSquareAndTinyWindows() {
        let square = CinemaEffect.pictureRect(settings: settings(.cinemascope), viewport: CGSize(width: 500, height: 500))
        XCTAssertEqual(square.height, 500 / 2.39, accuracy: 1e-9)
        let tiny = CinemaEffect.pictureRect(settings: settings(.flat), viewport: CGSize(width: 20, height: 40))
        XCTAssertEqual(tiny.width / tiny.height, 1.85, accuracy: 1e-9)
        XCTAssertGreaterThan(tiny.height, 0)
    }

    func testDisabledOrOffMeansNoBars() {
        let view = CGSize(width: 1200, height: 800)
        let full = CGRect(origin: .zero, size: view)
        XCTAssertEqual(CinemaEffect.pictureRect(settings: settings(.cinemascope, enabled: false), viewport: view), full)
        XCTAssertEqual(CinemaEffect.pictureRect(settings: settings(.off), viewport: view), full)
        let off = CinemaEffect.frame(settings: settings(.off), viewport: view, beat: 0, bass: 0, emphasisCenter: nil, time: 0)
        XCTAssertEqual(off?.barFraction, 0, "cinema on but no letterbox still gives a frame, without bars")
    }

    func testDegenerateViewsAreSafe() {
        for view in [CGSize.zero, CGSize(width: 0, height: 500), CGSize(width: 500, height: 0), CGSize(width: -3, height: 10)] {
            XCTAssertEqual(CinemaEffect.pictureRect(settings: settings(.cinemascope), viewport: view), CGRect(origin: .zero, size: view))
            XCTAssertNil(CinemaEffect.frame(settings: settings(.cinemascope), viewport: view, beat: 1, bass: 1, emphasisCenter: nil, time: 0))
        }
    }
}

final class CinemaFrameTests: XCTestCase {
    private let view = CGSize(width: 1200, height: 800)

    private func frame(_ mutate: (inout CinemaSettings) -> Void = { _ in }, beat: Float = 0, emphasis: CGPoint? = nil, time: Double = 0) -> CinemaFrame {
        var s = CinemaSettings()
        s.enabled = true
        mutate(&s)
        return CinemaEffect.frame(settings: s, viewport: view, beat: beat, bass: 0.5, emphasisCenter: emphasis, time: time)!
    }

    func testDisabledGivesNoFrameAtAll() {
        var s = CinemaSettings()
        s.enabled = false
        XCTAssertNil(CinemaEffect.frame(settings: s, viewport: view, beat: 1, bass: 1, emphasisCenter: nil, time: 0))
    }

    func testFlareFollowsTheBeatAndKeepsARestingLevel() {
        let resting = frame(beat: 0).flare, mid = frame(beat: 0.5).flare, hit = frame(beat: 1).flare
        XCTAssertGreaterThan(resting, 0, "alive between beats")
        XCTAssertLessThan(resting, mid)
        XCTAssertLessThan(mid, hit)
        XCTAssertEqual(hit, 0.5, accuracy: 1e-6, "full beat reaches the configured strength (default 0.5)")
        XCTAssertGreaterThan(frame(beat: 1).flareHalfWidth, frame(beat: 0).flareHalfWidth, "the streak stretches on a hit")
    }

    func testFlareSettingScalesAndZeroTurnsItOff() {
        XCTAssertEqual(frame({ $0.flare = 1 }, beat: 1).flare, 1, accuracy: 1e-6)
        XCTAssertEqual(frame({ $0.flare = 0.25 }, beat: 1).flare, 0.25, accuracy: 1e-6)
        XCTAssertEqual(frame({ $0.flare = 0 }, beat: 1).flare, 0)
        XCTAssertLessThanOrEqual(frame({ $0.flare = 7 }, beat: 5).flare, 1, "out-of-range input is clamped")
    }

    func testStreakCrossesTheEmphasisWordElseThePictureCentre() {
        let point = CGPoint(x: 300, y: 410)
        XCTAssertEqual(frame(emphasis: point).flareCenter, point)

        // With CinemaScope bars the picture's centre is still the view's centre vertically.
        let plain = frame()
        XCTAssertEqual(plain.flareCenter.x, 600, accuracy: 1e-9)
        XCTAssertEqual(plain.flareCenter.y, 400, accuracy: 1e-9)
    }

    func testGrainSeedHoldsForOneFilmFrameThenChanges() {
        let step = 1 / CinemaEffect.grainRate
        let a = frame(time: 10.0 + 0.0001).grainSeed
        XCTAssertEqual(frame(time: 10.0 + step * 0.9).grainSeed, a, "same seed within one 1/24 s step")
        XCTAssertNotEqual(frame(time: 10.0 + step * 1.05).grainSeed, a, "a new film frame changes the grain")
        XCTAssertNotEqual(frame(time: 10.0 + step * 2.05).grainSeed, frame(time: 10.0 + step * 1.05).grainSeed)
    }

    func testGrainSeedStaysExactlyRepresentableOverLongSessions() {
        for t in [0.0, 3_600, 86_400, 10_000_000] {
            let seed = frame(time: t).grainSeed
            XCTAssertTrue(seed >= 0 && seed < 4096)
            XCTAssertEqual(seed, seed.rounded(), "whole numbers only, no float drift")
        }
        XCTAssertEqual(frame(time: -5).grainSeed, 0, "negative time is treated as zero")
    }

    func testVignetteAndGrainPassThroughClamped() {
        XCTAssertEqual(frame({ $0.vignette = 0.3; $0.grain = 0.6 }).vignette, 0.3, accuracy: 1e-6)
        XCTAssertEqual(frame({ $0.vignette = 0.3; $0.grain = 0.6 }).grain, 0.6, accuracy: 1e-6)
        XCTAssertEqual(frame({ $0.vignette = 4; $0.grain = -2 }).vignette, 1)
        XCTAssertEqual(frame({ $0.vignette = 4; $0.grain = -2 }).grain, 0)
    }

    func testDeterministic() {
        XCTAssertEqual(frame(beat: 0.7, emphasis: CGPoint(x: 1, y: 2), time: 12.34), frame(beat: 0.7, emphasis: CGPoint(x: 1, y: 2), time: 12.34))
    }

    func testSettingsDecodeTolerantlyAndRoundTrip() throws {
        XCTAssertEqual(try JSONDecoder().decode(CinemaSettings.self, from: Data("{}".utf8)), CinemaSettings())
        var s = CinemaSettings()
        s.enabled = true
        s.letterbox = .flat
        s.flare = 0.9
        XCTAssertEqual(try JSONDecoder().decode(CinemaSettings.self, from: JSONEncoder().encode(s)), s)
        let p = try JSONDecoder().decode(PlayerSettings.self, from: Data(#"{"cinema":{"enabled":true,"letterbox":"nonsense"}}"#.utf8))
        XCTAssertTrue(p.cinema.enabled)
        XCTAssertEqual(p.cinema.letterbox, CinemaSettings().letterbox, "a malformed value falls back instead of failing")
    }
}
