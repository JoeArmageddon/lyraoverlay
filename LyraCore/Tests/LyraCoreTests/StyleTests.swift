import XCTest
@testable import LyraCore

/// 0.5 em per character, 1.2 em line height: deterministic, and different from LayoutTests' measurer.
private struct StubMeasurer: TextMeasuring {
    func width(of text: String, font: FontSpec) -> CGFloat { CGFloat(text.count) * CGFloat(font.size) * 0.5 }
    func lineHeight(font: FontSpec) -> CGFloat { CGFloat(font.size) * 1.2 }
}

/// Real word timing, so tests know exactly when each word starts: aa 1-2s, bb 2-3s, cc 3-4s.
private let timedLRC = "[00:01.00]<00:01.00>aa <00:02.00>bb <00:03.00>cc <00:04.00>\n[00:10.00]next line here\n[00:20.00]last one"

private let viewport = CGSize(width: 1000, height: 600)
private let measurer = StubMeasurer()

private func frame(_ lrc: String = timedLRC, at position: TimeInterval) throws -> LyricsFrame {
    let doc = try XCTUnwrap(LRCParser.parse(lrc))
    return LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: position), position: position)
}

private func layout(_ style: LyricStyle, _ lrc: String = timedLRC, at position: TimeInterval, config: OverlayConfig = OverlayConfig()) throws -> [DrawItem] {
    style.layout(try frame(lrc, at: position), viewport: viewport, config: config, measurer: measurer)
}

private let allStyles: [(id: String, style: LyricStyle)] = LyricStyles.all.map { ($0.id, LyricStyles.style(id: $0.id)) }

final class StyleInvariantTests: XCTestCase {
    func testEmptyLyricsDrawNothing() {
        let empty = LyricsFrame(lines: [], cursor: .before, position: 0)
        for (id, style) in allStyles {
            XCTAssertTrue(style.layout(empty, viewport: viewport, config: OverlayConfig(), measurer: measurer).isEmpty, id)
        }
    }

    func testItemsStayInsideTheViewportHorizontally() throws {
        let longLine = "[00:01.00]" + Array(repeating: "wordword", count: 14).joined(separator: " ") + "\n[00:30.00]end"
        for (id, style) in allStyles {
            for (lrc, positions) in [(timedLRC, [1.2, 2.5, 3.5, 5.0, 10.4]), (longLine, [1.5, 4.0, 9.0])] {
                for t in positions {
                    for item in try layout(style, lrc, at: t) where item.opacity > 0.01 {
                        let half = item.size.width * CGFloat(item.scale) / 2
                        XCTAssertGreaterThanOrEqual(item.center.x - half, -1, "\(id) at \(t)s: \(item.text) spills left")
                        XCTAssertLessThanOrEqual(item.center.x + half, viewport.width + 1, "\(id) at \(t)s: \(item.text) spills right")
                    }
                }
            }
        }
    }

    func testValuesAreInRange() throws {
        for (id, style) in allStyles {
            for t in stride(from: 0.0, through: 25.0, by: 0.37) {
                for item in try layout(style, at: t) {
                    XCTAssertTrue((0...1).contains(item.opacity), "\(id) opacity \(item.opacity) at \(t)s")
                    XCTAssertTrue((0...1).contains(item.progress), "\(id) progress \(item.progress) at \(t)s")
                    XCTAssertGreaterThan(item.scale, 0, id)
                    XCTAssertFalse(item.text.isEmpty, id)
                    XCTAssertTrue(item.center.x.isFinite && item.center.y.isFinite, id)
                }
            }
        }
    }

    func testLayoutIsDeterministic() throws {
        for (id, style) in allStyles {
            for t in [0.5, 1.7, 2.5, 3.3, 9.9, 10.2, 15] {
                XCTAssertEqual(try layout(style, at: t), try layout(style, at: t), "\(id) at \(t)s")
            }
        }
    }

    func testEveryStyleDrawsSomethingMidLine() throws {
        for (id, style) in allStyles {
            XCTAssertFalse(try layout(style, at: 2.5).isEmpty, id)
        }
    }

    func testDrawItemScaleDefaultsToOne() {
        let item = DrawItem(text: "x", font: FontSpec(size: 10), center: .zero, size: .zero, baseColor: .white,
                            highlightColor: .white, glowColor: .white, glow: 0, progress: 0, opacity: 1)
        XCTAssertEqual(item.scale, 1)
    }
}

final class ScrollingListStyleTests: XCTestCase {
    private let style = ScrollingListStyle()

    func testShowsSeveralLinesAndTheCurrentOneIsLargest() throws {
        let lrc = "[00:01.00]one one\n[00:05.00]two two\n[00:09.00]three three\n[00:13.00]four four\n[00:17.00]five five\n[00:21.00]six six"
        let items = try layout(style, lrc, at: 10.0)   // well after the glide into line three
        let lines = Set(items.map { $0.text }.filter { $0.contains(" ") || ["three", "two", "four", "one", "five"].contains($0) })
        XCTAssertGreaterThanOrEqual(lines.count, 4, "the current line (as words) plus neighbors")

        let current = items.filter { ["three"].contains($0.text) }
        XCTAssertFalse(current.isEmpty)
        let maxScale = items.map(\.scale).max() ?? 0
        XCTAssertEqual(maxScale, 1, accuracy: 1e-4)
        XCTAssertTrue(current.allSatisfy { $0.scale == maxScale })
        XCTAssertTrue(items.filter { $0.text.hasPrefix("four") || $0.text.hasPrefix("two") }.allSatisfy { $0.scale < 0.7 })
    }

    func testFartherLinesAreDimmer() throws {
        let lrc = "[00:01.00]one one\n[00:05.00]two two\n[00:09.00]three three\n[00:13.00]four four\n[00:17.00]five five"
        let items = try layout(style, lrc, at: 10.0)
        let near = items.first { $0.text == "four four" }?.opacity ?? 0
        let far = items.first { $0.text == "five five" }?.opacity ?? 0
        XCTAssertGreaterThan(near, far)
        XCTAssertGreaterThan(far, 0)
    }

    func testListGlidesUpwardBetweenLines() throws {
        let lrc = "[00:01.00]one one\n[00:05.00]two two\n[00:09.00]three three"
        // Line two starts at 5.0; its first word should slide up toward the anchor as the glide runs.
        func y(_ t: Double) throws -> CGFloat { try XCTUnwrap(try layout(style, lrc, at: t).first { $0.text == "two" }).center.y }
        let samples = try [5.02, 5.1, 5.2, 5.5].map(y)
        for (a, b) in zip(samples, samples.dropFirst()) { XCTAssertGreaterThan(a, b, "moving up (y decreases): \(samples)") }
        XCTAssertEqual(samples.last!, viewport.height * (1 - OverlayConfig().anchorY), accuracy: 0.5, "settles on the anchor")
    }

    func testFirstLineFadesInBeforeTheSongReachesIt() throws {
        let lrc = "[00:30.00]first line\n[00:35.00]second line"
        XCTAssertTrue(try layout(style, lrc, at: 5).isEmpty)
        let near = try layout(style, lrc, at: 28.5)
        XCTAssertFalse(near.isEmpty)
        XCTAssertTrue(near.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })
    }

    func testNoItemsForInstrumentalGaps() throws {
        let items = try layout(style, "[00:01.00]aa bb\n[00:05.00]\n[00:09.00]cc dd", at: 6)
        XCTAssertFalse(items.contains { $0.text.isEmpty })
    }
}

final class TypewriterStyleTests: XCTestCase {
    private let style = TypewriterStyle()

    func testUnsungWordsAreNotDrawn() throws {
        XCTAssertEqual(try layout(style, at: 1.2).map(\.text), ["aa"])
        XCTAssertEqual(try layout(style, at: 2.5).map(\.text), ["aa", "bb"])
    }

    func testRevealedWordsDoNotShiftAsMoreAppear() throws {
        let early = try XCTUnwrap(try layout(style, at: 1.2).first { $0.text == "aa" })
        let late = try XCTUnwrap(try layout(style, at: 3.5).first { $0.text == "aa" })
        XCTAssertEqual(early.center.x, late.center.x, accuracy: 0.001)
        XCTAssertEqual(early.center.y, late.center.y, accuracy: 0.001)
    }

    func testRevealIsDoneByWipeNotColor() throws {
        for item in try layout(style, at: 2.5) {
            XCTAssertEqual(item.baseColor.a, 0, "the unsung part of a word is invisible")
        }
    }

    func testOnlyFinishedWordsCastAShadow() throws {
        // "bb" is half typed at 2.5s: its invisible unsung half must not leave a dark halo behind.
        let items = try layout(style, at: 2.5)
        let partial = try XCTUnwrap(items.first { $0.text == "bb" })
        let done = try XCTUnwrap(items.first { $0.text == "aa" })
        XCTAssertEqual(partial.shadow, 0)
        XCTAssertEqual(done.shadow, OverlayConfig().shadow)
    }

    func testFinishedLineShowsEverything() throws {
        XCTAssertEqual(try layout(style, at: 6.0).filter { $0.progress == 1 }.map(\.text), ["aa", "bb", "cc"])
    }

    func testPreviousLineFadesOutAboveTheNewOne() throws {
        // Line two starts at 10.0.
        let start = try layout(style, at: 10.05)
        let previous = try XCTUnwrap(start.first { $0.text == "aa bb cc" || $0.text.contains("aa") && $0.text.contains("cc") })
        XCTAssertGreaterThan(previous.opacity, 0.9)
        XCTAssertLessThan(previous.font.size, OverlayConfig().font.size)

        let later = try layout(style, at: 11.5)
        XCTAssertFalse(later.contains { $0.text.contains("aa") }, "gone after the fade")
    }

    func testNothingBeforeTheFirstLine() throws {
        XCTAssertTrue(try layout(style, at: 0.2).isEmpty)
    }
}

final class PopStyleTests: XCTestCase {
    private let style = PopStyle()

    private func word(_ text: String, at t: Double) throws -> DrawItem {
        try XCTUnwrap(try layout(style, at: t).first { $0.text == text })
    }

    func testWordSwellsShortlyAfterItStarts() throws {
        XCTAssertGreaterThan(try word("aa", at: 1.05).scale, 1.05)
    }

    func testWordSettlesBackToRestSize() throws {
        let settled = try word("aa", at: 2.0 - 0.001)   // a full second after "aa" began
        XCTAssertEqual(settled.scale, 1, accuracy: 0.002)
    }

    func testWordsThatHaveNotStartedAreAtRest() throws {
        let future = try word("cc", at: 1.5)
        XCTAssertEqual(future.scale, 1, accuracy: 1e-6)
    }

    func testWordHopsUpAndComesBackDown() throws {
        let rest = try word("aa", at: 5.0).center.y
        let popping = try word("aa", at: 1.05).center.y
        XCTAssertLessThan(popping, rest, "y grows downward, so a hop has a smaller y")
        XCTAssertEqual(try word("aa", at: 1.99).center.y, rest, accuracy: 0.5)
    }

    func testSpringOvershootsAndDipsBelowRest() throws {
        // From just after the line starts: at exactly 1.0 the line's fade-in has not begun and nothing is drawn.
        let scales = try stride(from: 1.01, to: 1.6, by: 0.01).map { try word("aa", at: $0).scale }
        XCTAssertGreaterThan(scales.max()!, 1.08)
        XCTAssertLessThan(scales.min()!, 1.0, "a spring dips under rest size once before settling")
    }
}

final class WaveStyleTests: XCTestCase {
    private let style = WaveStyle()

    func testWordsSitAtDifferentHeightsOnTheWave() throws {
        let items = try layout(style, at: 1.1)
        XCTAssertGreaterThan(Set(items.map { $0.center.y.rounded(toPlaces: 2) }).count, 1)
    }

    func testTheWaveTravelsOverTime() throws {
        let a = try layout(style, at: 5.0).map(\.center.y)
        let b = try layout(style, at: 5.2).map(\.center.y)
        XCTAssertNotEqual(a, b)
    }

    func testAmplitudeStaysSmall() throws {
        let anchor = viewport.height * (1 - OverlayConfig().anchorY)
        for t in stride(from: 1.0, to: 6.0, by: 0.1) {
            for item in try layout(style, at: t) {
                XCTAssertLessThan(abs(item.center.y - anchor), OverlayConfig().font.size * 0.5, "words stay near the line at \(t)s")
            }
        }
    }

    func testCurrentWordLiftsAboveWhereItWouldBe() throws {
        // At the middle of "bb" (2.5s) it is lifted; at 4.5s the line is finished and nothing is being sung.
        let lifted = try XCTUnwrap(try layout(style, at: 2.5).first { $0.text == "bb" })
        let unlifted = try XCTUnwrap(try layout(style, at: 2.5).first { $0.text == "aa" })
        let anchor = viewport.height * (1 - OverlayConfig().anchorY)
        XCTAssertLessThan(lifted.center.y, anchor - OverlayConfig().font.size * 0.1)
        XCTAssertLessThan(lifted.center.y, unlifted.center.y + OverlayConfig().font.size * 0.1)
    }
}

final class FocusStyleTests: XCTestCase {
    private let style = FocusStyle()

    func testCurrentWordIsBigAndCentered() throws {
        let items = try layout(style, at: 2.5)
        let big = try XCTUnwrap(items.first { $0.text == "bb" && $0.font.size > OverlayConfig().font.size })
        XCTAssertEqual(big.center.x, viewport.width / 2, accuracy: 0.5)
        XCTAssertGreaterThan(big.font.size, OverlayConfig().font.size * 1.5)
        XCTAssertEqual(big.progress, 0.5, accuracy: 0.05)
    }

    func testTheWholeLineIsShownSmallBelow() throws {
        let items = try layout(style, at: 2.5)
        let small = items.filter { $0.font.size < OverlayConfig().font.size }
        XCTAssertEqual(small.map(\.text), ["aa", "bb", "cc"])
        let big = try XCTUnwrap(items.first { $0.font.size > OverlayConfig().font.size })
        XCTAssertTrue(small.allSatisfy { $0.center.y > big.center.y })
    }

    func testSungPartOfTheSmallLineIsMarked() throws {
        let small = try layout(style, at: 2.5).filter { $0.font.size < OverlayConfig().font.size }
        XCTAssertEqual(small.map(\.progress), [1, 0.5, 0], accuracy: 0.05)
    }

    func testBigWordChangesWithTheCurrentWord() throws {
        func bigText(_ t: Double) throws -> String? {
            try layout(style, at: t).first { $0.font.size > OverlayConfig().font.size && $0.progress < 1 || $0.scale >= 1 && $0.font.size > OverlayConfig().font.size }?.text
        }
        XCTAssertEqual(try bigText(1.5), "aa")
        XCTAssertEqual(try bigText(2.5), "bb")
        XCTAssertEqual(try bigText(3.5), "cc")
    }

    func testPreviousWordLeavesAsTheNextArrives() throws {
        let items = try layout(style, at: 2.05)   // "bb" just started
        let ghost = try XCTUnwrap(items.first { $0.text == "aa" && $0.font.size > OverlayConfig().font.size })
        XCTAssertGreaterThan(ghost.opacity, 0)
        XCTAssertLessThan(ghost.scale, 1.01)
        XCTAssertFalse(try layout(style, at: 2.6).contains { $0.text == "aa" && $0.font.size > OverlayConfig().font.size }, "the ghost is gone")
    }

    func testWordPopsInOnEntry() throws {
        let early = try XCTUnwrap(try layout(style, at: 2.04).first { $0.text == "bb" && $0.font.size > OverlayConfig().font.size })
        let settled = try XCTUnwrap(try layout(style, at: 2.9).first { $0.text == "bb" && $0.font.size > OverlayConfig().font.size })
        XCTAssertGreaterThan(early.scale, settled.scale)
        XCTAssertEqual(settled.scale, 1, accuracy: 0.01)
    }

    func testNoBigWordOnceTheLineIsSung() throws {
        let items = try layout(style, at: 6.0)
        XCTAssertTrue(items.allSatisfy { $0.font.size < OverlayConfig().font.size })
    }
}

final class LyricStylesRegistryTests: XCTestCase {
    func testIDsAreUniqueAndInOrder() {
        XCTAssertEqual(LyricStyles.all.map(\.id), ["karaoke", "scroll", "typewriter", "pop", "wave", "focus", "cinematic"])
        XCTAssertEqual(Set(LyricStyles.all.map(\.id)).count, LyricStyles.all.count)
        XCTAssertEqual(LyricStyles.all.map(\.name), ["Karaoke Line", "Scrolling List", "Typewriter", "Pop", "Wave", "Word Focus", "Cinematic"])
        XCTAssertTrue(LyricStyles.all.allSatisfy { !$0.summary.isEmpty })
    }

    func testStylesMatchTheirInfo() {
        for info in LyricStyles.all {
            XCTAssertEqual(LyricStyles.style(id: info.id).name, info.name, info.id)
        }
    }

    func testUnknownIDFallsBackToTheDefault() {
        XCTAssertEqual(LyricStyles.style(id: "nope").name, LyricStyles.style(id: LyricStyles.defaultID).name)
        XCTAssertEqual(LyricStyles.style(id: "").name, "Karaoke Line")
        XCTAssertEqual(LyricStyles.defaultID, "karaoke")
    }

    func testBuiltInThemesReferenceRealStyles() {
        let ids = Set(LyricStyles.all.map(\.id))
        for theme in BuiltInThemes.all { XCTAssertTrue(ids.contains(theme.styleID), "\(theme.name) uses \(theme.styleID)") }
    }

    func testNewStylesLookDifferentFromKaraoke() throws {
        let karaoke = try layout(KaraokeLineStyle(), at: 2.5)
        for info in LyricStyles.all where info.id != "karaoke" {
            XCTAssertNotEqual(try layout(LyricStyles.style(id: info.id), at: 2.5), karaoke, info.id)
        }
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let m = pow(10, CGFloat(places))
        return (self * m).rounded() / m
    }
}

/// Element-wise comparison with a tolerance, for arrays of Float.
private func XCTAssertEqual(_ a: [Float], _ b: [Float], accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
