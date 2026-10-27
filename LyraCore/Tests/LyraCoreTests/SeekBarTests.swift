import XCTest
@testable import LyraCore

final class SeekBarTests: XCTestCase {
    private let bar = SeekBar(duration: 200)

    func testFractionAndTimeAreInverseAndClamped() {
        XCTAssertEqual(bar.fraction(position: 50), 0.25, accuracy: 1e-9)
        XCTAssertEqual(bar.time(forFraction: 0.25), 50, accuracy: 1e-9)
        XCTAssertEqual(bar.fraction(position: -5), 0)
        XCTAssertEqual(bar.fraction(position: 999), 1, "a player briefly reporting past the end stays on the bar")
        XCTAssertEqual(bar.time(forFraction: -1), 0)
        XCTAssertEqual(bar.time(forFraction: 2), 200)
        for f in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(bar.fraction(position: bar.time(forFraction: f)), f, accuracy: 1e-9)
        }
    }

    func testPointerPositionMapsToTheBarAndStaysInside() {
        XCTAssertEqual(bar.fraction(forX: 100, width: 400), 0.25, accuracy: 1e-9)
        XCTAssertEqual(bar.fraction(forX: -20, width: 400), 0, "dragging left of the bar pins to the start")
        XCTAssertEqual(bar.fraction(forX: 900, width: 400), 1, "dragging right of the bar pins to the end")
        XCTAssertEqual(bar.fraction(forX: 10, width: 0), 0, "a zero-width bar can't divide by zero")
    }

    func testUnseekableDurationsAreHandled() {
        for duration in [0, 0.5, -3, .infinity, .nan] {
            let b = SeekBar(duration: duration)
            XCTAssertFalse(b.isSeekable, "\(duration)")
            XCTAssertEqual(b.fraction(position: 10), 0)
            XCTAssertEqual(b.time(forFraction: 0.5), 0)
            XCTAssertEqual(b.remainingText(position: 10), "--:--")
        }
        XCTAssertTrue(SeekBar(duration: 1).isSeekable)
    }

    func testInvalidInputsNeverProduceNaN() {
        XCTAssertEqual(bar.fraction(position: .nan), 0)
        XCTAssertEqual(bar.time(forFraction: .nan), 0)
        XCTAssertEqual(bar.fraction(forX: .nan, width: 100), 0)
    }

    func testTimeFormatting() {
        XCTAssertEqual(SeekBar.format(0), "0:00")
        XCTAssertEqual(SeekBar.format(7), "0:07")
        XCTAssertEqual(SeekBar.format(67.9), "1:07", "fractions are truncated, not rounded up")
        XCTAssertEqual(SeekBar.format(3599), "59:59")
        XCTAssertEqual(SeekBar.format(3600), "1:00:00")
        XCTAssertEqual(SeekBar.format(3723), "1:02:03")
        XCTAssertEqual(SeekBar.format(-4), "0:00")
        XCTAssertEqual(SeekBar.format(.nan), "0:00")
        XCTAssertEqual(SeekBar.format(.infinity), "0:00")
    }

    func testRemainingTimeCountsDown() {
        XCTAssertEqual(bar.remainingText(position: 0), "-3:20")
        XCTAssertEqual(bar.remainingText(position: 140), "-1:00")
        XCTAssertEqual(bar.remainingText(position: 200), "-0:00")
        XCTAssertEqual(bar.remainingText(position: 250), "-0:00", "never shows a time after the end")
    }
}

final class SeekCommandTests: XCTestCase {
    func testScriptUsesWholeMillisecondsAndTheRightApp() {
        let music = PlayerControl.seekScript(seconds: 12.5, player: .appleMusic)
        XCTAssertTrue(music.contains("tell application \"Music\" to set player position to (12500 / 1000)"), music)
        let spotify = PlayerControl.seekScript(seconds: 90, player: .spotify)
        XCTAssertTrue(spotify.contains("tell application \"Spotify\""), spotify)
        XCTAssertTrue(spotify.contains("(90000 / 1000)"), spotify)
    }

    func testScriptNeverContainsADecimalPointOrNegativeTime() {
        for seconds in [0.0, 0.0004, 3.14159, 12.5, 3599.999, -7] {
            let script = PlayerControl.seekScript(seconds: seconds, player: .appleMusic)
            let number = script.components(separatedBy: "position to (").last ?? ""
            XCTAssertFalse(number.prefix(while: { $0 != ")" }).contains("."), "a decimal literal breaks in comma locales: \(script)")
            XCTAssertFalse(number.contains("-"), "negative positions are clamped: \(script)")
        }
    }

    func testSeekScriptsCompile() throws {
        for (player, bundleID) in [(PlayerKind.appleMusic, "com.apple.Music"), (.spotify, "com.spotify.client")] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { continue }
            var error: NSDictionary?
            let script = try XCTUnwrap(NSAppleScript(source: PlayerControl.seekScript(seconds: 42.5, player: player)))
            XCTAssertTrue(script.compileAndReturnError(&error), "\(player) seek script failed to compile: \(String(describing: error))")
        }
    }

    func testSeekRefusesInvalidTimesAndAppsThatAreNotRunning() async {
        let nan = await PlayerControl.seek(to: .nan, player: .appleMusic)
        XCTAssertFalse(nan)
        let inf = await PlayerControl.seek(to: .infinity, player: .appleMusic)
        XCTAssertFalse(inf)
    }

    func testSessionSeekMovesTheClockOnlyWhenATrackIsLoaded() {
        let session = LyricsSession()
        session.noteSeek(to: 30)
        XCTAssertEqual(session.current.snapshot.position, 0, "with no track there is nothing to move")
    }
}
