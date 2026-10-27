import XCTest
@testable import LyraCore

/// Checks the real thing, not a fake: that macOS itself lists the assertion while the player
/// should keep the Mac awake, and stops listing it afterwards. (Unit tests with a fake
/// assertion cover the on/off policy; this proves the system call does what the app relies on.)
final class KeepAwakeSystemTests: XCTestCase {
    private let reason = "Lyra is showing lyrics"

    /// What `pmset -g assertions` currently says.
    private func assertionsListing() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Waits for the listing to reach the wanted state; the system reports changes a moment late.
    private func waitForListing(containing wanted: Bool, timeout: TimeInterval = 3) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try assertionsListing().contains(reason) == wanted { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }

    func testTheSystemListsTheAssertionOnlyWhilePlayingAndVisible() throws {
        let awake = KeepAwake()
        try XCTSkipIf(try assertionsListing().isEmpty, "pmset is unavailable")
        XCTAssertFalse(try assertionsListing().contains(reason), "nothing is held before the player runs")

        awake.update(enabled: true, windowVisible: true, playing: true)
        XCTAssertTrue(awake.isActive)
        XCTAssertTrue(try waitForListing(containing: true), "macOS should list the display-sleep assertion while playing")

        // Pausing releases it: the display is allowed to sleep again.
        awake.update(enabled: true, windowVisible: true, playing: false)
        XCTAssertFalse(awake.isActive)
        XCTAssertTrue(try waitForListing(containing: false), "the assertion must disappear when playback stops")

        // Resuming takes it again, hiding the window releases it, and closing releases it for good.
        awake.update(enabled: true, windowVisible: true, playing: true)
        XCTAssertTrue(try waitForListing(containing: true))
        awake.update(enabled: true, windowVisible: false, playing: true)
        XCTAssertTrue(try waitForListing(containing: false), "a hidden window must not keep the Mac awake")

        awake.update(enabled: true, windowVisible: true, playing: true)
        awake.releaseNow()
        XCTAssertTrue(try waitForListing(containing: false), "releasing on close leaves nothing behind")
    }

    func testTurningTheSettingOffNeverHoldsTheAssertion() throws {
        let awake = KeepAwake()
        awake.update(enabled: false, windowVisible: true, playing: true)
        XCTAssertFalse(awake.isActive)
        XCTAssertFalse(try assertionsListing().contains(reason))
    }
}
