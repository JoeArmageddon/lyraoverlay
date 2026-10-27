import XCTest
@testable import LyraCore

/// 0.5 em per character, 1.2 em line height: exact and linear, so layout assertions are exact too.
private struct Stub: TextMeasuring {
    func width(of text: String, font: FontSpec) -> CGFloat {
        // Tracking is in em and adds to every character, like the real measurer.
        CGFloat(text.count) * CGFloat(font.size) * (0.5 + CGFloat(font.tracking))
    }
    func lineHeight(font: FontSpec) -> CGFloat { CGFloat(font.size) * 1.2 }
}

private let viewport = CGSize(width: 1000, height: 600)
private let measurer = Stub()

/// Invented lines of varied length (none from a real song), four seconds apart.
private let sampleLines = [
    "Salt on the wind",
    "Run",
    "We were bright as the hours before the storm broke open",
    "Hold on",
    "Every window lit a different kind of fire tonight",
    "Silence",
    "Somebody left the lights on in the old harbor",
    "Again and again and again",
    "Gold dust on the water, ash on the sky, a long road home by morning",
    "Now",
    "Carry me back to the shore",
    "Never look down",
]

private func lrc(_ lines: [String], every seconds: Int = 4, from first: Int = 2) -> String {
    lines.enumerated().map { i, text in
        let t = first + i * seconds
        return String(format: "[%02d:%02d.00]%@", t / 60, t % 60, text)
    }.joined(separator: "\n")
}

private func frame(_ lyrics: String, at position: TimeInterval, beat: Float = 0, bass: Float = 0) throws -> LyricsFrame {
    let doc = try XCTUnwrap(LRCParser.parse(lyrics))
    return LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: position), position: position, beat: beat, bass: bass)
}

private func layout(_ style: LyricStyle, _ lyrics: String, at position: TimeInterval, beat: Float = 0, bass: Float = 0,
                    config: OverlayConfig = OverlayConfig()) throws -> [DrawItem] {
    style.layout(try frame(lyrics, at: position, beat: beat, bass: bass), viewport: viewport, config: config, measurer: measurer)
}

/// The default cinematic style.
private func layout(_ lyrics: String, at position: TimeInterval, beat: Float = 0, bass: Float = 0,
                    config: OverlayConfig = OverlayConfig()) throws -> [DrawItem] {
    try layout(CinematicStyle(), lyrics, at: position, beat: beat, bass: bass, config: config)
}

private func words(_ n: Int) -> String {
    (0..<n).map { ["ember", "tide", "glass", "north", "paper", "orbit", "velvet", "harbor", "static", "lantern"][$0 % 10] + ($0 >= 10 ? "\($0)" : "") }
        .joined(separator: " ")
}

private func assertInside(_ items: [DrawItem], _ message: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
    for item in items {
        let half = item.size.width * CGFloat(item.scale) / 2
        XCTAssertGreaterThanOrEqual(item.center.x - half, -1, "\(message()): \(item.text) spills left", file: file, line: line)
        XCTAssertLessThanOrEqual(item.center.x + half, viewport.width + 1, "\(message()): \(item.text) spills right", file: file, line: line)
        XCTAssertTrue(item.center.x.isFinite && item.center.y.isFinite && item.scale.isFinite, "\(message()): not finite", file: file, line: line)
        XCTAssertTrue((0...1).contains(item.opacity), "\(message()): opacity \(item.opacity)", file: file, line: line)
        XCTAssertTrue((0...1).contains(item.progress), "\(message()): progress \(item.progress)", file: file, line: line)
        XCTAssertTrue((0...1).contains(item.blur), "\(message()): blur \(item.blur)", file: file, line: line)
        XCTAssertGreaterThan(item.scale, 0, message(), file: file, line: line)
    }
}

// MARK: - Emphasis

final class EmphasisPickerTests: XCTestCase {
    func testStopWordsAreSkipped() {
        XCTAssertEqual(EmphasisPicker.index(of: ["the", "big", "and", "dream"]), 3)
        XCTAssertEqual(EmphasisPicker.index(of: ["you", "are", "my", "lantern", "to", "the", "sea"]), 3)
    }

    func testLongerContentWordWins() {
        XCTAssertEqual(EmphasisPicker.index(of: ["we", "remember", "gold", "again"]), 1)
    }

    func testClauseEndingPunctuationBoosts() {
        XCTAssertEqual(EmphasisPicker.index(of: ["love", "hurts!", "slowly"]), 1)
        XCTAssertEqual(EmphasisPicker.index(of: ["where", "now?", "go"]), 1, "'now?' beats the longer 'where'")
        XCTAssertEqual(EmphasisPicker.index(of: ["where", "now", "go"]), 0, "without the question mark, length wins")
    }

    func testAllCapsBoosts() {
        XCTAssertEqual(EmphasisPicker.index(of: ["we", "SHOUT", "it"]), 1)
    }

    func testLastWordNudgeAndTiesGoToTheLaterWord() {
        XCTAssertEqual(EmphasisPicker.index(of: ["gold", "moon"]), 1)
        XCTAssertEqual(EmphasisPicker.index(of: ["gold", "moon", "dust"]), 2, "equal lengths: the later word")
    }

    func testSingleWordAndEmpty() {
        XCTAssertEqual(EmphasisPicker.index(of: ["Run"]), 0)
        XCTAssertEqual(EmphasisPicker.index(of: []), 0)
        XCTAssertEqual(EmphasisPicker.index(of: ["the"]), 0)
    }

    func testPunctuationOnlyTokensAreNeverPicked() {
        XCTAssertEqual(EmphasisPicker.index(of: ["—", "hello"]), 1)
        XCTAssertEqual(EmphasisPicker.index(of: ["hello", "—"]), 0)
    }

    func testAllStopWordsStillPickSomething() {
        let pick = EmphasisPicker.index(of: ["to", "the"])
        XCTAssertTrue([0, 1].contains(pick))
    }

    func testApostrophesDoNotHideStopWords() {
        // "don't" is a stop word once the apostrophe is dropped; "stay" is the content word.
        XCTAssertEqual(EmphasisPicker.index(of: ["don't", "stay", "i'm", "gone"]), 3)
        XCTAssertEqual(EmphasisPicker.index(of: ["don't", "forget", "me"]), 1)
    }

    func testCJKPicksTheMiddle() {
        XCTAssertEqual(EmphasisPicker.index(of: ["夜", "空", "下", "的", "城", "市"]), 3)
        XCTAssertEqual(EmphasisPicker.index(of: ["こ", "ん", "に", "ち", "は"]), 2)
    }

    func testMixedScriptsFallBackToTheScore() {
        XCTAssertEqual(EmphasisPicker.index(of: ["夜", "lantern", "空"]), 1)
    }
}

// MARK: - Shots

final class CinematicShotTests: XCTestCase {
    private let all = lrc(sampleLines)

    func testOutputIsDeterministic() throws {
        for t in [2.05, 2.4, 3.0, 6.3, 9.9, 14.2, 30.5, 49.0] {
            XCTAssertEqual(try layout(all, at: t), try layout(all, at: t), "at \(t)s")
        }
    }

    func testTemplatesVaryAndNeverRepeatBackToBack() throws {
        let doc = try XCTUnwrap(LRCParser.parse(all))
        let names = try doc.lines.indices.map { try XCTUnwrap(CinematicStyle.describeShot(lineIndex: $0, in: doc.lines)).template }
        XCTAssertGreaterThanOrEqual(Set(names).count, 4, "variety: \(names)")
        for (a, b) in zip(names, names.dropFirst()) { XCTAssertNotEqual(a, b, "back to back: \(names)") }
    }

    func testShortLinesFavourTheHeroAndLongLinesTheWall() throws {
        // A single word opening a song has no recent shots to avoid: it is the hero.
        let opener = try XCTUnwrap(LRCParser.parse("[00:01.00]Run\n[00:05.00]next line"))
        XCTAssertEqual(CinematicStyle.describeShot(lineIndex: 0, in: opener.lines)?.template, "hero")

        // Over a song, short lines are mostly heroes or other big-word shots, never a crowded scatter.
        let doc = try XCTUnwrap(LRCParser.parse(all))
        for i in [1, 3, 5, 9] {   // "Run", "Hold on", "Silence", "Now"
            let t = try XCTUnwrap(CinematicStyle.describeShot(lineIndex: i, in: doc.lines)).template
            // (A two-word line split corner to corner is a good shot too.)
            XCTAssertTrue(["hero", "wall", "stackLeft", "stackRight", "diagonal"].contains(t), "line \(i): \(t)")
        }
        // A very long line is a poster block or a stack, a sparse shot would leave words stranded.
        let veryLong = try XCTUnwrap(LRCParser.parse("[00:01.00]\(words(16))\n[00:09.00]x"))
        let long = try XCTUnwrap(CinematicStyle.describeShot(lineIndex: 0, in: veryLong.lines)).template
        XCTAssertTrue(["wall", "stackLeft", "diagonal"].contains(long), long)
    }

    func testTheSampleSongUsesMostTemplatesNotJustTwoOrThree() throws {
        let doc = try XCTUnwrap(LRCParser.parse(all))
        let names = try doc.lines.indices.map { try XCTUnwrap(CinematicStyle.describeShot(lineIndex: $0, in: doc.lines)).template }
        XCTAssertGreaterThanOrEqual(Set(names).count, 5, "\(names)")
        let busiest = Dictionary(grouping: names, by: { $0 }).values.map(\.count).max() ?? 0
        XCTAssertLessThanOrEqual(busiest, 4, "no template should take a third of the song: \(names)")
    }

    func testChoicesDoNotDependOnWhereYouStartLooking() throws {
        // The template chain is defined from the first line, so asking about line 5 alone must
        // give the same answer as walking there.
        let doc = try XCTUnwrap(LRCParser.parse(all))
        let walked = doc.lines.indices.map { CinematicStyle.describeShot(lineIndex: $0, in: doc.lines)?.template }
        for i in [5, 9, 3, 11] { XCTAssertEqual(CinematicStyle.describeShot(lineIndex: i, in: doc.lines)?.template, walked[i]) }
    }

    func testEveryTemplateStaysInsideForEveryLineSizeAndTransition() throws {
        let texts = [
            "Run", "Hold on", words(4), words(12), words(30),
            String(repeating: "Supercalifragilistic", count: 4),           // one very long word
        ]
        for template in ShotTemplate.allCases {
            for transition in ShotTransition.allCases {
                let style = CinematicStyle(forcing: template, transition: transition)
                for text in texts {
                    let lyrics = lrc([text, "next line here"], every: 10)
                    for t in [2.0, 2.02, 2.1, 2.2, 2.5, 4.0, 6.0, 7.0] {
                        assertInside(try layout(style, lyrics, at: t), "\(template) \(transition) \(text.prefix(18)) at \(t)s")
                    }
                }
            }
        }
    }

    func testExactlyOneHeroItemAndItIsThePickedWord() throws {
        for template in ShotTemplate.allCases {
            let style = CinematicStyle(forcing: template, transition: .cut)
            for text in sampleLines {
                let lyrics = lrc([text, "next"], every: 10)
                let items = try layout(style, lyrics, at: 3.0)
                let heroes = items.filter(\.isEmphasis)
                XCTAssertEqual(heroes.count, 1, "\(template) '\(text)'")
                let tokens = text.split(separator: " ").map(String.init)
                XCTAssertEqual(heroes.first?.text, tokens[EmphasisPicker.index(of: tokens)], "\(template) '\(text)'")
            }
        }
    }

    func testEveryWordOfALineIsDrawn() throws {
        for template in ShotTemplate.allCases where template != .scatter {
            let style = CinematicStyle(forcing: template, transition: .cut)
            let text = "Gold dust on the water ash on the sky"
            let items = try layout(style, lrc([text, "next"], every: 10), at: 3.0)
            XCTAssertEqual(items.map(\.text).sorted(), text.split(separator: " ").map(String.init).sorted(), "\(template)")
        }
    }

    func testScatterGroupsWordsIntoAtMostSixPhrases() throws {
        let style = CinematicStyle(forcing: .scatter, transition: .cut)
        let long = words(14)
        let items = try layout(style, lrc([long, "next"], every: 20), at: 12.0)   // late enough that everything has appeared
        XCTAssertLessThanOrEqual(items.count, 6)
        XCTAssertEqual(items.map(\.text).joined(separator: " ").split(separator: " ").count, 14, "no word is lost")
    }

    func testScatterPhrasesAppearAsTheyAreSung() throws {
        let timed = "[00:01.00]<00:01.00>ember <00:02.00>tide <00:03.00>glass <00:04.00>north <00:05.00>paper <00:06.00>orbit <00:07.00>\n[00:30.00]end"
        let style = CinematicStyle(forcing: .scatter, transition: .cut)
        func visible(_ t: Double) throws -> Int { try layout(style, timed, at: t).filter { $0.opacity > 0.5 }.count }
        let counts = try [1.5, 3.5, 5.5, 6.5].map(visible)
        XCTAssertLessThan(counts[0], counts[3], "later in the line, more of it is on screen: \(counts)")
        XCTAssertEqual(counts, counts.sorted(), "phrases never disappear while the line plays: \(counts)")
    }

    func testWallFillsTheFrame() throws {
        let style = CinematicStyle(forcing: .wall, transition: .cut)
        let items = try layout(style, lrc([words(12), "next"], every: 20), at: 3.0)
        let left = items.map { $0.center.x - $0.size.width * CGFloat($0.scale) / 2 }.min() ?? 0
        let right = items.map { $0.center.x + $0.size.width * CGFloat($0.scale) / 2 }.max() ?? 0
        XCTAssertGreaterThan(right - left, 0.7 * viewport.width, "a poster block spans most of the width")
        let top = items.map(\.center.y).min() ?? 0, bottom = items.map(\.center.y).max() ?? 0
        XCTAssertGreaterThan(bottom - top, 0.3 * viewport.height, "and several rows of height")
    }

    func testHeroWordIsHuge() throws {
        let style = CinematicStyle(forcing: .hero, transition: .cut)
        let items = try layout(style, lrc(["hold the storm", "next"], every: 20), at: 2.05)
        let hero = try XCTUnwrap(items.first(where: \.isEmphasis))
        XCTAssertGreaterThan(hero.size.width, 0.45 * viewport.width)
        let others = items.filter { !$0.isEmphasis }
        XCTAssertTrue(others.allSatisfy { $0.font.size < hero.font.size / 2 }, "supporting words are small")
    }

    func testStackLeftAndRightHugTheirMargins() throws {
        let line = lrc(["silver rivers run home", "next"], every: 20)
        let left = try layout(CinematicStyle(forcing: .stackLeft, transition: .cut), line, at: 3.0)
        let right = try layout(CinematicStyle(forcing: .stackRight, transition: .cut), line, at: 3.0)
        XCTAssertLessThan(left.map { $0.center.x - $0.size.width * CGFloat($0.scale) / 2 }.max() ?? 0, 0.2 * viewport.width)
        XCTAssertGreaterThan(right.map { $0.center.x + $0.size.width * CGFloat($0.scale) / 2 }.min() ?? 0, 0.8 * viewport.width)
        let ys = left.map(\.center.y)
        XCTAssertEqual(ys, ys.sorted(), "stacked in reading order, top to bottom")
    }

    func testNeighbouringWordsOfASingleRowDoNotOverlap() throws {
        for template in [ShotTemplate.hero, .titleCard, .diagonal, .wall] {
            let items = try layout(CinematicStyle(forcing: template, transition: .cut), lrc([words(8), "next"], every: 20), at: 3.0)
            for a in items { for b in items where a.text != b.text && abs(a.center.y - b.center.y) < 2 {
                let overlap = min(a.center.x + a.size.width * CGFloat(a.scale) / 2, b.center.x + b.size.width * CGFloat(b.scale) / 2)
                            - max(a.center.x - a.size.width * CGFloat(a.scale) / 2, b.center.x - b.size.width * CGFloat(b.scale) / 2)
                XCTAssertLessThanOrEqual(overlap, 1, "\(template): \(a.text) overlaps \(b.text)")
            } }
        }
    }

    func testEveryItemCarriesLineAndWordIndex() throws {
        let doc = try XCTUnwrap(LRCParser.parse(all))
        for template in ShotTemplate.allCases {
            let style = CinematicStyle(forcing: template)
            let f = try frame(all, at: 11.0)
            let items = style.layout(f, viewport: viewport, config: OverlayConfig(), measurer: measurer)
            XCTAssertFalse(items.isEmpty, "\(template)")
            for item in items {
                XCTAssertEqual(item.lineIndex, f.cursor.lineIndex, "\(template)")
                XCTAssertTrue(doc.lines[item.lineIndex ?? 0].words.indices.contains(item.wordIndex), "\(template) wordIndex \(item.wordIndex)")
            }
        }
    }

    func testCJKAndEmptyLinesDoNotCrash() throws {
        let cjk = "[00:01.00]夜空下的城市灯火通明\n[00:09.00]こんにちは世界\n[00:17.00]end"
        for t in [1.1, 3.0, 9.2, 12.0] { assertInside(try layout(cjk, at: t), "cjk at \(t)s") }
        XCTAssertTrue(try layout("[00:01.00]hello", at: 0.2).isEmpty, "before the first line")
    }

    func testGapsAndTheTimeBeforeTheFirstLineDrawNothing() throws {
        let gappy = "[00:02.00]hold the storm\n[00:06.00]\n[00:14.00]after the gap"
        XCTAssertTrue(try layout(gappy, at: 1.0).isEmpty)
        XCTAssertTrue(try layout(gappy, at: 8.0).isEmpty, "an instrumental gap shows nothing")
        XCTAssertFalse(try layout(gappy, at: 14.5).isEmpty)
    }
}

// MARK: - Camera and transitions

final class CinematicMotionTests: XCTestCase {
    /// One long line (8 s) so the move is slow and the sample window stays inside the shot.
    private let long = lrc(["hold the storm back", "next line"], every: 8)

    private func hero(_ style: CinematicStyle, at t: Double) throws -> DrawItem {
        try XCTUnwrap(try layout(style, long, at: t).first(where: \.isEmphasis))
    }

    func testEveryCameraMoveIsContinuous() throws {
        for move in CameraMove.allCases {
            let style = CinematicStyle(forcing: .hero, camera: move, transition: .cut)
            var previous = try hero(style, at: 2.3)
            var t = 2.3 + 1.0 / 60
            while t < 5.0 {
                let now = try hero(style, at: t)
                XCTAssertLessThan(hypot(now.center.x - previous.center.x, now.center.y - previous.center.y), 2.5, "\(move) jumped at \(t)s")
                XCTAssertLessThan(abs(now.scale - previous.scale), 0.002, "\(move) scale jumped at \(t)s")
                previous = now
                t += 1.0 / 60
            }
        }
    }

    func testPushInGrowsAndPullOutShrinks() throws {
        let push = CinematicStyle(forcing: .hero, camera: .pushIn, transition: .cut)
        let pull = CinematicStyle(forcing: .hero, camera: .pullOut, transition: .cut)
        let ts = stride(from: 2.3, to: 6.0, by: 0.25).map { $0 }
        let up = try ts.map { try hero(push, at: $0).scale }
        let down = try ts.map { try hero(pull, at: $0).scale }
        for (a, b) in zip(up, up.dropFirst()) { XCTAssertGreaterThanOrEqual(b, a) }
        for (a, b) in zip(down, down.dropFirst()) { XCTAssertLessThanOrEqual(b, a) }
        XCTAssertGreaterThan(up.last!, up.first!)
        XCTAssertLessThan(down.last!, down.first!)
        XCTAssertLessThanOrEqual(up.last!, 1.075, "a slow push, not a lunge")
    }

    func testPansMoveTheShotTheRightWay() throws {
        let left = CinematicStyle(forcing: .hero, camera: .panLeft, transition: .cut)
        let right = CinematicStyle(forcing: .hero, camera: .panRight, transition: .cut)
        XCTAssertGreaterThan(try hero(left, at: 2.3).center.x, try hero(left, at: 6.0).center.x)
        XCTAssertLessThan(try hero(right, at: 2.3).center.x, try hero(right, at: 6.0).center.x)
        let up = CinematicStyle(forcing: .hero, camera: .panUp, transition: .cut)
        XCTAssertGreaterThan(try hero(up, at: 2.3).center.y, try hero(up, at: 6.0).center.y)
    }

    func testEntranceStartsAwayFromAndEndsExactlyAtTheSettledShot() throws {
        for template in [ShotTemplate.hero, .diagonal, .wall, .stackLeft] {
            let cut = CinematicStyle(forcing: template, camera: .drift, transition: .cut)
            for transition in [ShotTransition.whip, .zoomThrough, .riseSettle] {
                let style = CinematicStyle(forcing: template, camera: .drift, transition: transition)
                // Early: not where the settled shot is.
                let early = try layout(style, long, at: 2.02), settledEarly = try layout(cut, long, at: 2.02)
                XCTAssertNotEqual(early, settledEarly, "\(template) \(transition) should start somewhere else")
                XCTAssertTrue(early.contains { $0.blur > 0 || $0.opacity < 1 }, "\(template) \(transition)")

                // Done (the longest transition plus the longest word delay): identical to a hard cut.
                for t in [2.5, 3.0, 4.5] {
                    XCTAssertEqual(try layout(style, long, at: t), try layout(cut, long, at: t), "\(template) \(transition) at \(t)s")
                }
            }
        }
    }

    func testEveryTransitionFinishesQuickly() {
        for t in ShotTransition.allCases { XCTAssertLessThanOrEqual(t.duration, 0.25, "\(t)") }
    }

    func testCutIsInstant() throws {
        let style = CinematicStyle(forcing: .hero, camera: .pushIn, transition: .cut)
        let items = try layout(style, long, at: 2.0)
        XCTAssertTrue(items.allSatisfy { $0.opacity == 1 && $0.blur == 0 })
    }

    func testNoEntranceSettingForcesHardCuts() throws {
        var config = OverlayConfig()
        config.fadeInDuration = 0   // what LyricsPipeline sets for an entrance of "none"
        let items = try layout(CinematicStyle(forcing: .hero, transition: .whip), long, at: 2.0, config: config)
        XCTAssertTrue(items.allSatisfy { $0.opacity == 1 && $0.blur == 0 })
    }

    func testTheShotLeavesAfterTheLineIsSung() throws {
        let style = CinematicStyle(forcing: .hero, transition: .cut)
        let doc = try XCTUnwrap(LRCParser.parse(long))
        let end = doc.lines[0].sungEnd
        XCTAssertEqual(try layout(style, long, at: end + 0.2).first?.opacity, 1, "held briefly after the last word")
        let midExit = try layout(style, long, at: end + 0.45 + 0.1)
        XCTAssertTrue(midExit.allSatisfy { $0.opacity < 1 && $0.opacity > 0 }, "fading out")
        XCTAssertTrue(try layout(style, long, at: end + 0.45 + 0.3).isEmpty, "gone before the next line")
    }
}

// MARK: - Beat and bass

final class CinematicBeatTests: XCTestCase {
    private let lyrics = lrc(["hold the storm back", "next"], every: 10)

    func testNoBeatAndNoBassAddNothing() throws {
        let style = CinematicStyle(forcing: .hero, camera: .drift, transition: .cut)
        XCTAssertEqual(try layout(style, lyrics, at: 4.0, beat: 0, bass: 0), try layout(style, lyrics, at: 4.0))
    }

    func testBeatPunchesTheHeroOnlyByUpToFourPercent() throws {
        let style = CinematicStyle(forcing: .hero, camera: .drift, transition: .cut)
        let calm = try layout(style, lyrics, at: 4.0)
        let hit = try layout(style, lyrics, at: 4.0, beat: 1)
        for (a, b) in zip(calm, hit) {
            if a.isEmphasis {
                XCTAssertEqual(b.scale / a.scale, 1.04, accuracy: 0.001)
            } else {
                XCTAssertEqual(a, b, "only the hero word punches")
            }
        }
        let half = try layout(style, lyrics, at: 4.0, beat: 0.5)
        let hero = try XCTUnwrap(half.first(where: \.isEmphasis)), calmHero = try XCTUnwrap(calm.first(where: \.isEmphasis))
        XCTAssertEqual(hero.scale / calmHero.scale, 1.02, accuracy: 0.001, "the punch scales with the beat")
    }

    func testBassShakesEverythingASmallDeterministicAmount() throws {
        let style = CinematicStyle(forcing: .hero, camera: .drift, transition: .cut)
        let calm = try layout(style, lyrics, at: 4.0)
        let shaken = try layout(style, lyrics, at: 4.0, bass: 1)
        XCTAssertEqual(shaken, try layout(style, lyrics, at: 4.0, bass: 1), "deterministic")
        for (a, b) in zip(calm, shaken) {
            let d = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
            XCTAssertGreaterThan(d, 0, "every word moves")
            XCTAssertLessThan(d, 0.006 * min(viewport.width, viewport.height) * 1.5, "but only a few points")
        }
        let weaker = try layout(style, lyrics, at: 4.0, bass: 0.25)
        let d1 = hypot(calm[0].center.x - shaken[0].center.x, calm[0].center.y - shaken[0].center.y)
        let d2 = hypot(calm[0].center.x - weaker[0].center.x, calm[0].center.y - weaker[0].center.y)
        XCTAssertLessThan(d2, d1, "a quieter bass shakes less")
    }

    func testOutOfRangeBeatIsClamped() throws {
        let style = CinematicStyle(forcing: .hero, camera: .drift, transition: .cut)
        XCTAssertEqual(try layout(style, lyrics, at: 4.0, beat: 5, bass: 9), try layout(style, lyrics, at: 4.0, beat: 1, bass: 1))
        XCTAssertEqual(try layout(style, lyrics, at: 4.0, beat: -1, bass: -1), try layout(style, lyrics, at: 4.0))
    }
}

// MARK: - Registry and pipeline

final class CinematicIntegrationTests: XCTestCase {
    func testRegistryEndsWithCinematic() {
        XCTAssertEqual(LyricStyles.all.count, 7)
        XCTAssertEqual(LyricStyles.all.last?.id, "cinematic")
        XCTAssertEqual(LyricStyles.all.last?.name, "Cinematic")
        XCTAssertEqual(LyricStyles.style(id: "cinematic").name, "Cinematic")
    }

    func testPipelineWithDefaultConfigMatchesTheStyleExactly() throws {
        let lyrics = lrc(sampleLines)
        let style = LyricStyles.style(id: "cinematic")
        for t in [2.02, 2.1, 3.0, 6.1, 14.5, 30.2] {
            let f = try frame(lyrics, at: t, beat: 0.3, bass: 0.2)
            XCTAssertEqual(
                LyricsPipeline.items(style: style, frame: f, viewport: viewport, config: OverlayConfig(), measurer: measurer),
                style.layout(f, viewport: viewport, config: OverlayConfig(), measurer: measurer), "at \(t)s")
        }
    }

    func testAnEntranceChosenInSettingsStacksOnTop() throws {
        var config = OverlayConfig()
        config.entrance = .zoomIn
        let f = try frame(lrc(sampleLines), at: 6.05)
        let plain = CinematicStyle().layout(f, viewport: viewport, config: OverlayConfig(), measurer: measurer)
        let stacked = LyricsPipeline.items(style: CinematicStyle(), frame: f, viewport: viewport, config: config, measurer: measurer)
        XCTAssertNotEqual(plain, stacked)
        XCTAssertEqual(plain.count, stacked.count)
    }

    func testNoEntranceMakesCinematicCut() throws {
        var config = OverlayConfig()
        config.entrance = .none
        let f = try frame(lrc(sampleLines), at: 2.03)
        let items = LyricsPipeline.items(style: CinematicStyle(forcing: .hero, transition: .whip), frame: f, viewport: viewport, config: config, measurer: measurer)
        XCTAssertTrue(items.allSatisfy { $0.opacity == 1 && $0.blur == 0 })
    }

    func testDescribeShotForGapsAndOutOfRange() throws {
        let doc = try XCTUnwrap(LRCParser.parse("[00:01.00]hello there\n[00:05.00]\n[00:09.00]again"))
        XCTAssertNil(CinematicStyle.describeShot(lineIndex: 1, in: doc.lines))
        XCTAssertNil(CinematicStyle.describeShot(lineIndex: 9, in: doc.lines))
        XCTAssertNotNil(CinematicStyle.describeShot(lineIndex: 0, in: doc.lines))
    }
}
