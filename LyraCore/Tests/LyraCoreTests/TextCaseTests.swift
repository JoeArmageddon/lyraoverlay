import XCTest
@testable import LyraCore

final class TextCaseTests: XCTestCase {
    func testAsWrittenIsUntouched() {
        XCTAssertEqual(TextCase.asWritten.apply("Hello, wORLD!"), "Hello, wORLD!")
    }

    func testUpperAndLower() {
        XCTAssertEqual(TextCase.upper.apply("Hello, wORLD! it's 3am"), "HELLO, WORLD! IT'S 3AM")
        XCTAssertEqual(TextCase.lower.apply("Hello, wORLD! it's 3AM"), "hello, world! it's 3am")
    }

    func testTitleCaseCapitalizesWordStartsAndLowercasesTheRest() {
        XCTAssertEqual(TextCase.title.apply("hello wORLD of mIXed"), "Hello World Of Mixed")
        XCTAssertEqual(TextCase.title.apply("don't stop, ok?"), "Don't Stop, Ok?")
    }

    func testTitleCaseSkipsLeadingPunctuationAndKeepsDigitWords() {
        XCTAssertEqual(TextCase.title.apply("(hello) \"quoted\" word"), "(Hello) \"Quoted\" Word")
        XCTAssertEqual(TextCase.title.apply("3am again"), "3am Again")
    }

    func testTitleCasePreservesSpacingAndEmptyStrings() {
        XCTAssertEqual(TextCase.title.apply("a  b\tc"), "A  B\tC")
        XCTAssertEqual(TextCase.title.apply(""), "")
    }

    func testResultDoesNotDependOnTheCurrentLocale() {
        // Turkish would turn "i" into a dotted capital I under a locale-aware transform.
        XCTAssertEqual(TextCase.upper.apply("title"), "TITLE")
        XCTAssertEqual(TextCase.title.apply("iris"), "Iris")
    }

    func testEveryCaseHasADisplayTitle() {
        XCTAssertEqual(Set(TextCase.allCases.map(\.title)).count, TextCase.allCases.count)
    }

    // MARK: - Documents

    private var document: LyricsDocument {
        LRCParser.parse("[00:01.00]hello big world\n[00:05.00]\n[00:09.00]Second LINE")!
    }

    func testApplyingKeepsTimingsCountsAndFlags() throws {
        let doc = document
        let upper = doc.applying(.upper)
        XCTAssertEqual(upper.lines.count, doc.lines.count)
        XCTAssertEqual(upper.isSynced, doc.isSynced)
        XCTAssertEqual(upper.hasWordTiming, doc.hasWordTiming)
        XCTAssertEqual(upper.source, doc.source)
        XCTAssertEqual(upper.lines[0].text, "HELLO BIG WORLD")
        XCTAssertEqual(upper.lines[0].words.map(\.text), ["HELLO", "BIG", "WORLD"])
        for (a, b) in zip(doc.lines, upper.lines) {
            XCTAssertEqual(a.start, b.start)
            XCTAssertEqual(a.end, b.end)
            XCTAssertEqual(a.sungEnd, b.sungEnd)
            XCTAssertEqual(a.words.map(\.start), b.words.map(\.start))
            XCTAssertEqual(a.words.map(\.end), b.words.map(\.end))
            XCTAssertEqual(a.words.map(\.isEstimated), b.words.map(\.isEstimated))
        }
        XCTAssertTrue(upper.lines[1].isInstrumentalGap, "gaps stay gaps")
    }

    func testApplyingAsWrittenReturnsTheSameDocument() {
        XCTAssertEqual(document.applying(.asWritten), document)
    }

    func testApplyingLeavesPlainTextAlone() {
        var doc = document
        doc.plainText = "Original Plain Text"
        XCTAssertEqual(doc.applying(.lower).plainText, "Original Plain Text")
    }

    func testApplyingTitleCaseOnWords() {
        let titled = document.applying(.title)
        XCTAssertEqual(titled.lines[2].text, "Second Line")
        XCTAssertEqual(titled.lines[2].words.map(\.text), ["Second", "Line"])
    }
}

final class FontSpecCodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testOldFontJSONWithoutNewKeysDecodesToDefaults() throws {
        let f = try decode(FontSpec.self, #"{"family":"Helvetica Neue","size":40,"weight":0.2}"#)
        XCTAssertEqual(f.family, "Helvetica Neue")
        XCTAssertEqual(f.size, 40)
        XCTAssertEqual(f.weight, 0.2, accuracy: 1e-9)
        XCTAssertEqual(f.tracking, 0)
        XCTAssertFalse(f.italic)
    }

    func testOldOverlayConfigWithoutTextCaseOrTrackingStillLoads() throws {
        let c = try decode(OverlayConfig.self, #"{"font":{"family":"System","size":50,"weight":0.4},"glow":0.3}"#)
        XCTAssertEqual(c.textCase, .asWritten)
        XCTAssertEqual(c.font.tracking, 0)
        XCTAssertEqual(c.font.size, 50)
        XCTAssertEqual(c.glow, 0.3, accuracy: 1e-6)
    }

    func testEmptyObjectsGiveDefaults() throws {
        XCTAssertEqual(try decode(OverlayConfig.self, "{}"), OverlayConfig())
        XCTAssertEqual(try decode(FontSpec.self, "{}").family, "System")
    }

    func testRoundTripKeepsTrackingItalicAndTextCase() throws {
        var c = OverlayConfig()
        c.font = FontSpec(family: "Avenir Next", size: 52, weight: 0.3, tracking: 0.08, italic: true)
        c.textCase = .upper
        let json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        let back = try decode(OverlayConfig.self, json)
        XCTAssertEqual(back, c)
        XCTAssertEqual(back.font.tracking, 0.08, accuracy: 1e-9)
        XCTAssertTrue(back.font.italic)
        XCTAssertEqual(back.textCase, .upper)
    }

    func testMalformedNewKeysFallBack() throws {
        let f = try decode(FontSpec.self, #"{"family":"X","size":30,"tracking":"wide","italic":3}"#)
        XCTAssertEqual(f.tracking, 0)
        XCTAssertFalse(f.italic)
    }

    func testWithSizeKeepsTrackingAndItalic() {
        let f = FontSpec(family: "X", size: 40, weight: 0.1, tracking: 0.05, italic: true).withSize(20)
        XCTAssertEqual(f.size, 20)
        XCTAssertEqual(f.tracking, 0.05)
        XCTAssertTrue(f.italic)
        XCTAssertEqual(f.weight, 0.1)
    }

    func testTrackingAndItalicAffectEquality() {
        let base = FontSpec(size: 40)
        XCTAssertNotEqual(base, FontSpec(size: 40, tracking: 0.1))
        XCTAssertNotEqual(base, FontSpec(size: 40, italic: true))
    }
}
