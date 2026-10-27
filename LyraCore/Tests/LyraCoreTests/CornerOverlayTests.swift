import XCTest
@testable import LyraCore

final class CornerOverlayTests: XCTestCase {
    /// A 1512x982 screen with a 33 pt menu bar on top and a 70 pt Dock at the bottom.
    private let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)

    private func settings(_ corner: ScreenCorner, margin: Double = 20) -> CornerOverlaySettings {
        var s = CornerOverlaySettings()
        s.corner = corner
        s.margin = margin
        return s
    }

    func testEachCornerSitsAgainstItsEdgesByTheMargin() {
        let size = CornerOverlay.size(for: settings(.topLeft))
        let tl = CornerOverlay.frame(in: visible, settings: settings(.topLeft))
        XCTAssertEqual(tl.minX, 20); XCTAssertEqual(tl.maxY, visible.maxY - 20)
        let tr = CornerOverlay.frame(in: visible, settings: settings(.topRight))
        XCTAssertEqual(tr.maxX, visible.maxX - 20); XCTAssertEqual(tr.maxY, visible.maxY - 20)
        let bl = CornerOverlay.frame(in: visible, settings: settings(.bottomLeft))
        XCTAssertEqual(bl.minX, 20); XCTAssertEqual(bl.minY, visible.minY + 20)
        let br = CornerOverlay.frame(in: visible, settings: settings(.bottomRight))
        XCTAssertEqual(br.maxX, visible.maxX - 20); XCTAssertEqual(br.minY, visible.minY + 20)
        for frame in [tl, tr, bl, br] { XCTAssertEqual(frame.size, size) }
    }

    func testTheCardStaysInsideTheVisibleAreaClearOfMenuBarAndDock() {
        for corner in ScreenCorner.allCases {
            let f = CornerOverlay.frame(in: visible, settings: settings(corner))
            XCTAssertTrue(visible.contains(f), "\(corner): \(f)")
        }
    }

    func testWorksOnADisplayWithANonZeroOrigin() {
        let secondScreen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let f = CornerOverlay.frame(in: secondScreen, settings: settings(.bottomRight, margin: 30))
        XCTAssertEqual(f.maxX, secondScreen.maxX - 30)
        XCTAssertEqual(f.minY, secondScreen.minY + 30)
        XCTAssertTrue(secondScreen.contains(f))
    }

    func testSizeGrowsWithTextAndNextLine() {
        var s = CornerOverlaySettings()
        let small = CornerOverlay.size(for: s)
        s.fontSize = 36
        let big = CornerOverlay.size(for: s)
        XCTAssertGreaterThan(big.height, small.height)
        s.showNextLine = true
        XCTAssertGreaterThan(CornerOverlay.size(for: s).height, big.height, "room for the preview line")
    }

    func testAbsurdValuesAreClamped() {
        var s = CornerOverlaySettings()
        s.fontSize = 5000; s.width = 100_000; s.margin = -50
        let size = CornerOverlay.size(for: s)
        XCTAssertLessThanOrEqual(size.width, CornerOverlay.widthRange.upperBound)
        XCTAssertLessThanOrEqual(size.height, CornerOverlay.fontSizeRange.upperBound * CornerOverlay.rowsWithNext + 2 * CornerOverlay.padding + 1)
        s.fontSize = -3; s.width = 1
        XCTAssertGreaterThanOrEqual(CornerOverlay.size(for: s).width, CornerOverlay.widthRange.lowerBound)
        XCTAssertGreaterThanOrEqual(CornerOverlay.clampedFontSize(s), CornerOverlay.fontSizeRange.lowerBound)
        XCTAssertGreaterThanOrEqual(CornerOverlay.frame(in: visible, settings: s).minX, visible.minX, "a negative margin can't push it off-screen")
    }

    func testAScreenSmallerThanTheCardShrinksIt() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 80)
        let f = CornerOverlay.frame(in: tiny, settings: settings(.topLeft))
        XCTAssertTrue(tiny.contains(f))
        XCTAssertGreaterThan(f.width, 0)
        XCTAssertGreaterThan(f.height, 0)
    }

    func testConfigIsCompactAndKeepsTheUsersLook() {
        var base = OverlayConfig()
        base.font = FontSpec(family: "Menlo-Bold", size: 60, weight: 0.3, tracking: 0.05)
        base.glow = 1.2
        var s = CornerOverlaySettings()
        s.fontSize = 20
        let c = CornerOverlay.config(from: base, settings: s)
        XCTAssertEqual(c.font.size, 20)
        XCTAssertEqual(c.font.family, "Menlo-Bold", "the chosen typeface carries over")
        XCTAssertEqual(c.font.tracking, 0.05)
        XCTAssertLessThanOrEqual(c.glow, 0.35)
        XCTAssertFalse(c.showNextLine)
        XCTAssertEqual(c.anchorY, 0.5)
        XCTAssertGreaterThanOrEqual(c.baseColor.a, 0.62, "unsung words stay readable on a small translucent card")
        XCTAssertGreaterThanOrEqual(c.secondaryScale, 0.72, "the preview line is big enough to read")
        s.showNextLine = true
        XCTAssertGreaterThan(CornerOverlay.config(from: base, settings: s).anchorY, 0.5)
    }

    func testBackdropFollowsTheSettings() throws {
        var s = CornerOverlaySettings()
        let size = CGSize(width: 380, height: 100)
        let panel = try XCTUnwrap(CornerOverlay.backdrop(for: s, size: size))
        XCTAssertEqual(panel.rect, CGRect(origin: .zero, size: size))
        XCTAssertEqual(panel.color.a, Float(s.backdropOpacity), accuracy: 1e-6)
        XCTAssertLessThanOrEqual(panel.cornerRadius, 25)
        s.showBackdrop = false
        XCTAssertNil(CornerOverlay.backdrop(for: s, size: size))
        s.showBackdrop = true; s.backdropOpacity = 0
        XCTAssertNil(CornerOverlay.backdrop(for: s, size: size), "fully transparent means no panel at all")
        s.backdropOpacity = 7
        XCTAssertEqual(try XCTUnwrap(CornerOverlay.backdrop(for: s, size: size)).color.a, 1, "opacity is clamped")
    }

    func testDecodingIsTolerantAndRoundTrips() throws {
        let empty = try JSONDecoder().decode(CornerOverlaySettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, CornerOverlaySettings())
        XCTAssertFalse(empty.enabled, "corner mode is opt-in")

        let bad = try JSONDecoder().decode(CornerOverlaySettings.self, from: Data(#"{"corner": "middle", "width": "wide", "enabled": true}"#.utf8))
        XCTAssertEqual(bad.corner, .bottomRight, "an unknown corner falls back")
        XCTAssertEqual(bad.width, CornerOverlaySettings().width)
        XCTAssertTrue(bad.enabled)

        var s = CornerOverlaySettings()
        s.enabled = true; s.corner = .topLeft; s.fontSize = 30; s.showNextLine = true; s.backdropOpacity = 0.7
        XCTAssertEqual(try JSONDecoder().decode(CornerOverlaySettings.self, from: JSONEncoder().encode(s)), s)
    }
}
