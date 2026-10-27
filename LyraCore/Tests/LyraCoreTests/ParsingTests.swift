import XCTest
@testable import LyraCore

final class LRCParserTests: XCTestCase {
    func testBasicLinesAndTags() throws {
        let doc = try XCTUnwrap(LRCParser.parse("[ar:Someone]\n[00:01.00]Hello world\n[00:05.50]Second line\n"))
        XCTAssertEqual(doc.lines.count, 2)
        XCTAssertEqual(doc.lines[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(doc.lines[0].end, 5.5, accuracy: 0.001)
        XCTAssertEqual(doc.lines[0].words.map(\.text), ["Hello", "world"])
        XCTAssertTrue(doc.lines[0].words.allSatisfy(\.isEstimated))
        XCTAssertFalse(doc.hasWordTiming)
        XCTAssertTrue(doc.isSynced)
    }

    func testRepeatedTimestampsAreSortedIntoSeparateLines() throws {
        let doc = try XCTUnwrap(LRCParser.parse("[00:10.00][01:00.00]Chorus\n[00:20.00]Verse"))
        XCTAssertEqual(doc.lines.map(\.text), ["Chorus", "Verse", "Chorus"])
        XCTAssertEqual(doc.lines.map(\.start), [10, 20, 60])
    }

    func testOffsetShiftsLyricsEarlier() throws {
        let doc = try XCTUnwrap(LRCParser.parse("[offset:500]\n[00:02.00]A"))
        XCTAssertEqual(doc.lines[0].start, 1.5, accuracy: 0.001)
    }

    func testFractionDigits() throws {
        XCTAssertEqual(try XCTUnwrap(LRCParser.parse("[00:01.5]x")).lines[0].start, 1.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LRCParser.parse("[00:01.25]x")).lines[0].start, 1.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LRCParser.parse("[00:01.250]x")).lines[0].start, 1.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LRCParser.parse("[01:01]x")).lines[0].start, 61, accuracy: 0.001)
    }

    func testEnhancedWordTimingIsKept() throws {
        let doc = try XCTUnwrap(LRCParser.parse("[00:01.00]<00:01.00>Hello <00:01.50>world <00:02.00>"))
        let line = doc.lines[0]
        XCTAssertEqual(line.text, "Hello world")
        XCTAssertEqual(line.words.count, 2)
        XCTAssertTrue(doc.hasWordTiming)
        XCTAssertFalse(line.words[0].isEstimated)
        XCTAssertEqual(line.words[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(line.words[0].end, 1.5, accuracy: 0.001)
        XCTAssertEqual(line.words[1].end, 2.0, accuracy: 0.001)
        XCTAssertEqual(line.sungEnd, 2.0, accuracy: 0.001)
    }

    func testBlankTimestampedLineIsInstrumentalGap() throws {
        let doc = try XCTUnwrap(LRCParser.parse("[00:01.00]A\n[00:03.00]\n[00:09.00]B"))
        XCTAssertEqual(doc.lines.count, 3)
        XCTAssertTrue(doc.lines[1].isInstrumentalGap)
        XCTAssertTrue(doc.lines[1].words.isEmpty)
    }

    func testSungEndIsCappedForLongGaps() throws {
        let doc = try XCTUnwrap(LRCParser.parse("[00:01.00]Short\n[00:40.00]Later"))
        XCTAssertLessThan(doc.lines[0].sungEnd, 10)
        XCTAssertEqual(doc.lines[0].end, 40, accuracy: 0.001)
    }

    func testTextWithoutTimestampsReturnsNil() {
        XCTAssertNil(LRCParser.parse("just\nplain\ntext"))
        XCTAssertNil(LRCParser.parse("[ar:Only tags]"))
    }
}

final class WordTimingTests: XCTestCase {
    func testSyllableEstimates() {
        XCTAssertEqual(WordTiming.syllables(in: "love"), 1)
        XCTAssertEqual(WordTiming.syllables(in: "time"), 1)
        XCTAssertEqual(WordTiming.syllables(in: "little"), 2)
        XCTAssertEqual(WordTiming.syllables(in: "beautiful"), 3)
        XCTAssertEqual(WordTiming.syllables(in: "I"), 1)
        XCTAssertEqual(WordTiming.syllables(in: "..."), 1)
    }

    func testInterpolationCoversTheWholeSpanWithoutGaps() {
        let words = WordTiming.interpolate(text: "one two three", start: 10, end: 14)
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words.first?.start ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(words.last?.end ?? 0, 14, accuracy: 1e-9)
        for (a, b) in zip(words, words.dropFirst()) { XCTAssertEqual(a.end, b.start, accuracy: 1e-9) }
    }

    func testLongerWordsGetMoreTime() {
        let words = WordTiming.interpolate(text: "a extraordinary", start: 0, end: 4)
        XCTAssertGreaterThan(words[1].end - words[1].start, words[0].end - words[0].start)
    }

    func testPunctuationAddsAPause() {
        let words = WordTiming.interpolate(text: "go, go", start: 0, end: 4)
        XCTAssertGreaterThan(words[0].end - words[0].start, words[1].end - words[1].start)
    }

    func testCJKSplitsPerCharacter() {
        XCTAssertEqual(WordTiming.tokenize("你好 world").count, 3)
        XCTAssertEqual(WordTiming.tokenize("こんにちは"), ["こ", "ん", "に", "ち", "は"])
    }

    func testEmptyTextHasNoWords() {
        XCTAssertTrue(WordTiming.interpolate(text: "   ", start: 0, end: 1).isEmpty)
    }
}

final class LyricsCursorTests: XCTestCase {
    private func cursor(_ lrc: String) throws -> LyricsCursor {
        LyricsCursor(document: try XCTUnwrap(LRCParser.parse(lrc)))
    }

    func testBeforeFirstLine() throws {
        XCTAssertEqual(try cursor("[00:01.00]Hello world").state(at: 0.5), .before)
    }

    func testTracksLineAndWord() throws {
        let c = try cursor("[00:01.00]Hello world\n[00:10.00]Next")
        let early = c.state(at: 1.1)
        XCTAssertEqual(early.lineIndex, 0)
        XCTAssertEqual(early.wordIndex, 0)
        XCTAssertTrue(early.isSinging)

        // "Hello" (2 syllables) takes two thirds of the sung span, so "world" starts near 2.5s.
        let later = c.state(at: 3.0)
        XCTAssertEqual(later.lineIndex, 0)
        XCTAssertEqual(later.wordIndex, 1)
    }

    func testGapAfterSungSpanKeepsLineButStopsSinging() throws {
        let c = try cursor("[00:01.00]Hello world\n[00:10.00]Next")
        let gap = c.state(at: 9.5)
        XCTAssertEqual(gap.lineIndex, 0)
        XCTAssertFalse(gap.isSinging)
        XCTAssertNil(gap.wordIndex)
        XCTAssertEqual(c.state(at: 10.5).lineIndex, 1)
    }

    func testInstrumentalGapIsNotSinging() throws {
        let c = try cursor("[00:01.00]A\n[00:03.00]\n[00:09.00]B")
        let s = c.state(at: 5)
        XCTAssertEqual(s.lineIndex, 1)
        XCTAssertFalse(s.isSinging)
    }

    func testRealWordTimingDrivesWordProgress() throws {
        let c = try cursor("[00:01.00]<00:01.00>Hello <00:02.00>world <00:03.00>")
        let s = c.state(at: 1.5)
        XCTAssertEqual(s.wordIndex, 0)
        XCTAssertEqual(s.wordProgress, 0.5, accuracy: 0.01)
    }
}
