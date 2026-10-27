import XCTest
@testable import LyraCore

/// Width is 0.5 em per character, line height 1.2 em: simple and deterministic.
private struct FakeMeasurer: TextMeasuring {
    func width(of text: String, font: FontSpec) -> CGFloat { CGFloat(text.count) * CGFloat(font.size) * 0.5 }
    func lineHeight(font: FontSpec) -> CGFloat { CGFloat(font.size) * 1.2 }
}

final class KaraokeLineStyleTests: XCTestCase {
    private let style = KaraokeLineStyle()
    private let measurer = FakeMeasurer()
    private let viewport = CGSize(width: 1000, height: 600)

    private func frame(_ lrc: String, at position: TimeInterval) throws -> LyricsFrame {
        let doc = try XCTUnwrap(LRCParser.parse(lrc))
        return LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: position), position: position)
    }

    private func layout(_ lrc: String, at position: TimeInterval, config: OverlayConfig = OverlayConfig()) throws -> [DrawItem] {
        style.layout(try frame(lrc, at: position), viewport: viewport, config: config, measurer: measurer)
    }

    func testEmptyLyricsDrawNothing() {
        XCTAssertTrue(style.layout(LyricsFrame(lines: [], cursor: .before, position: 0), viewport: viewport, config: OverlayConfig(), measurer: measurer).isEmpty)
    }

    func testCurrentLineIsCenteredAtTheAnchor() throws {
        var config = OverlayConfig()
        config.showNextLine = false
        let items = try layout("[00:01.00]one two three", at: 1.5, config: config)
        XCTAssertEqual(items.map(\.text), ["one", "two", "three"])

        let left = items.first!.center.x - items.first!.size.width / 2
        let right = items.last!.center.x + items.last!.size.width / 2
        XCTAssertEqual((left + right) / 2, viewport.width / 2, accuracy: 0.5)
        for item in items { XCTAssertEqual(item.center.y, viewport.height * (1 - config.anchorY), accuracy: 0.5) }
    }

    func testWordsAreOrderedAndNeverOverlap() throws {
        var config = OverlayConfig()
        config.showNextLine = false
        let items = try layout("[00:01.00]aa bbb cccc", at: 1.5, config: config)
        for (a, b) in zip(items, items.dropFirst()) {
            XCTAssertLessThanOrEqual(a.center.x + a.size.width / 2, b.center.x - b.size.width / 2)
        }
    }

    func testLongLineWrapsIntoCenteredRowsWithinMaxWidth() throws {
        var config = OverlayConfig()
        config.showNextLine = false
        let text = Array(repeating: "wordword", count: 12).joined(separator: " ")   // far wider than the view
        let items = try layout("[00:01.00]\(text)", at: 1.5, config: config)
        let rows = Set(items.map { $0.center.y }).sorted()
        XCTAssertGreaterThan(rows.count, 1)

        let centerRows = Set(items.map(\.center.y))
        let maxWidth = viewport.width * config.maxWidthFraction
        for y in centerRows {
            let inRow = items.filter { $0.center.y == y }
            let left = inRow.map { $0.center.x - $0.size.width / 2 }.min()!
            let right = inRow.map { $0.center.x + $0.size.width / 2 }.max()!
            XCTAssertLessThanOrEqual(right - left, maxWidth + 0.5)
            XCTAssertEqual((left + right) / 2, viewport.width / 2, accuracy: 0.5)
        }
        // Rows stay vertically centered on the anchor.
        let mid = (rows.first! + rows.last!) / 2
        XCTAssertEqual(mid, viewport.height * (1 - config.anchorY), accuracy: 0.5)
    }

    func testWordProgressFollowsTheCursor() throws {
        var config = OverlayConfig()
        config.showNextLine = false
        let items = try layout("[00:01.00]<00:01.00>aa <00:02.00>bb <00:03.00>cc <00:04.00>", at: 2.5, config: config)
        XCTAssertEqual(items.map(\.progress), [1, 0.5, 0])
    }

    func testFinishedLineShowsEverythingSung() throws {
        var config = OverlayConfig()
        config.showNextLine = false
        let items = try layout("[00:01.00]hi there\n[00:30.00]later", at: 12, config: config)
        XCTAssertTrue(items.allSatisfy { $0.progress == 1 })
    }

    func testLineFadesInThenOutAfterTheLinger() throws {
        var config = OverlayConfig()
        config.showNextLine = false
        let lrc = "[00:10.00]hi there\n[00:60.00]later"
        let start = try layout(lrc, at: 10.0, config: config)
        XCTAssertTrue(start.isEmpty || start[0].opacity < 0.05, "starts transparent")
        XCTAssertEqual(try layout(lrc, at: 11.0, config: config).first?.opacity ?? 0, 1, accuracy: 0.001)
        XCTAssertTrue(try layout(lrc, at: 40, config: config).isEmpty, "long after the line it is gone")
    }

    func testNextLinePreviewIsSmallerDimmerAndBelow() throws {
        let items = try layout("[00:01.00]current line\n[00:10.00]coming up", at: 1.5)
        let preview = try XCTUnwrap(items.last)
        XCTAssertEqual(preview.text, "coming up")
        XCTAssertEqual(preview.progress, 0)
        XCTAssertLessThan(preview.font.size, OverlayConfig().font.size)
        XCTAssertGreaterThan(preview.center.y, items.first!.center.y)
        XCTAssertLessThan(preview.baseColor.a, 1)
    }

    func testPreviewShrinksToFitWideLines() throws {
        let wide = String(repeating: "x", count: 200)
        let items = try layout("[00:01.00]hi\n[00:10.00]\(wide)", at: 1.5)
        let preview = try XCTUnwrap(items.last)
        XCTAssertLessThanOrEqual(preview.size.width, viewport.width * OverlayConfig().maxWidthFraction + 0.5)
    }

    func testBeforeFirstLinePreviewsItOnlyWhenClose() throws {
        let lrc = "[00:30.00]first line"
        XCTAssertTrue(try layout(lrc, at: 5).isEmpty, "far from the first line: nothing")
        let near = try layout(lrc, at: 28)
        XCTAssertEqual(near.first?.text, "first line")
        XCTAssertGreaterThan(near.first?.opacity ?? 0, 0)
    }

    func testInstrumentalGapShowsOnlyThePreview() throws {
        let items = try layout("[00:01.00]a b\n[00:05.00]\n[00:09.00]next one", at: 6)
        XCTAssertEqual(items.map(\.text), ["next one"])
    }
}
