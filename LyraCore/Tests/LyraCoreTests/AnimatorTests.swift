import XCTest
@testable import LyraCore

/// 0.5 em per character, 1.2 em line height: simple and deterministic.
private struct AnimMeasurer: TextMeasuring {
    func width(of text: String, font: FontSpec) -> CGFloat { CGFloat(text.count) * CGFloat(font.size) * 0.5 }
    func lineHeight(font: FontSpec) -> CGFloat { CGFloat(font.size) * 1.2 }
}

private let measurer = AnimMeasurer()
private let viewport = CGSize(width: 1200, height: 600)
/// Line 0 runs from 1 s; line 1 is the preview shown beneath it.
private let document = LRCParser.parse("[00:01.00]one two three four\n[00:10.00]next line here")!

private func frame(_ position: TimeInterval) -> LyricsFrame {
    LyricsFrame(lines: document.lines, cursor: LyricsCursor(document: document).state(at: position), position: position)
}

/// The style's own layout (with no baked fade-in, so items exist at the very first frame) and
/// the same items after the animator.
private func animate(_ position: TimeInterval, entrance: EntranceAnimation = .fade, exit: ExitAnimation = .fade,
                 tweak: (inout OverlayConfig) -> Void = { _ in }) -> (plain: [DrawItem], animated: [DrawItem]) {
    var config = OverlayConfig()
    config.fadeInDuration = 0
    config.entranceDuration = 1.0
    config.entranceStagger = 0.1
    tweak(&config)
    let plain = KaraokeLineStyle().layout(frame(position), viewport: viewport, config: config, measurer: measurer)
    config.entrance = entrance
    config.exit = exit
    return (plain, Animator.apply(plain, frame: frame(position), config: config))
}

private let animated = EntranceAnimation.allCases.filter { $0 != .none && $0 != .fade }
private func current(_ items: [DrawItem]) -> [DrawItem] { items.filter { $0.lineIndex == 0 }.sorted { $0.wordIndex < $1.wordIndex } }

final class AnimatorEntranceTests: XCTestCase {
    func testFadeAndNoneAddNothing() {
        for e in [EntranceAnimation.none, .fade] {
            for x in [ExitAnimation.none, .fade] {
                for position in [1.0, 1.3, 3.0, 6.0] {
                    let r = animate(position, entrance: e, exit: x)
                    XCTAssertFalse(r.plain.isEmpty)
                    XCTAssertEqual(r.animated, r.plain, "\(e) / \(x) at \(position)")
                }
            }
        }
    }

    func testEveryEntranceChangesTheFirstFrame() {
        for kind in animated {
            let r = animate(1.0, entrance: kind)
            XCTAssertFalse(current(r.plain).isEmpty)
            XCTAssertNotEqual(current(r.animated), current(r.plain), "\(kind) must look different at age 0")
        }
    }

    func testEveryEntranceEndsExactlyOnTheStylesLayout() {
        // 1.0 s duration, 0.1 s stagger over four words: everything is finished by 1 + 1 + 0.3.
        for kind in animated {
            let r = animate(2.45, entrance: kind)
            XCTAssertEqual(r.animated, r.plain, "\(kind) must leave no trace once finished")
        }
    }

    func testEveryEntranceIsDeterministic() {
        for kind in animated {
            for position in [1.0, 1.1, 1.37, 1.8] {
                XCTAssertEqual(animate(position, entrance: kind).animated, animate(position, entrance: kind).animated, "\(kind)")
            }
        }
    }

    func testRiseDropAndSlidesMoveTowardTheirPlace() {
        func first(_ kind: EntranceAnimation, _ position: TimeInterval) -> (plain: DrawItem, animated: DrawItem) {
            let r = animate(position, entrance: kind)
            return (current(r.plain)[0], current(r.animated)[0])
        }
        // Rise starts below (larger y) and moves up to its place.
        let rise0 = first(.rise, 1.0), riseMid = first(.rise, 1.4)
        XCTAssertGreaterThan(rise0.animated.center.y, riseMid.animated.center.y)
        XCTAssertGreaterThan(riseMid.animated.center.y, riseMid.plain.center.y)
        // Drop starts above.
        let drop0 = first(.drop, 1.0), dropMid = first(.drop, 1.4)
        XCTAssertLessThan(drop0.animated.center.y, dropMid.animated.center.y)
        XCTAssertLessThan(dropMid.animated.center.y, dropMid.plain.center.y)
        // Slides come from their own side.
        let l0 = first(.slideLeft, 1.0), lMid = first(.slideLeft, 1.4)
        XCTAssertLessThan(l0.animated.center.x, lMid.animated.center.x)
        XCTAssertLessThan(lMid.animated.center.x, lMid.plain.center.x)
        let r0 = first(.slideRight, 1.0), rMid = first(.slideRight, 1.4)
        XCTAssertGreaterThan(r0.animated.center.x, rMid.animated.center.x)
        XCTAssertGreaterThan(rMid.animated.center.x, rMid.plain.center.x)
    }

    func testZoomsScaleTowardOne() {
        func scale(_ kind: EntranceAnimation, _ position: TimeInterval) -> Float { current(animate(position, entrance: kind).animated)[0].scale }
        XCTAssertEqual(scale(.zoomIn, 1.0), 0.6, accuracy: 0.001)
        XCTAssertLessThan(scale(.zoomIn, 1.4), 1)
        XCTAssertGreaterThan(scale(.zoomIn, 1.4), scale(.zoomIn, 1.0))
        XCTAssertEqual(scale(.zoomOut, 1.0), 1.6, accuracy: 0.001)
        XCTAssertGreaterThan(scale(.zoomOut, 1.4), 1)
        XCTAssertLessThan(scale(.zoomOut, 1.4), scale(.zoomOut, 1.0))
    }

    func testZoomScalesTheWholeLineAboutItsCenter() {
        // Words move toward the line's center along with shrinking, so the line zooms as one piece.
        let r = animate(1.0, entrance: .zoomIn)
        let plain = current(r.plain), anim = current(r.animated)
        let lineCenterX = (plain.map(\.center.x).min()! + plain.map(\.center.x).max()!) / 2
        let plainSpan = plain.last!.center.x - plain.first!.center.x
        let animSpan = anim.last!.center.x - anim.first!.center.x
        XCTAssertEqual(animSpan, plainSpan * 0.6, accuracy: 0.5)
        XCTAssertEqual((anim.map(\.center.x).min()! + anim.map(\.center.x).max()!) / 2, lineCenterX, accuracy: 0.5)
    }

    func testSpringOvershootsThenSettlesAtOne() {
        let scales = stride(from: 1.0, through: 2.0, by: 0.02).map { current(animate($0, entrance: .spring).animated)[0].scale }
        XCTAssertLessThan(scales.first!, 0.7, "starts small")
        XCTAssertGreaterThan(scales.max()!, 1.05, "overshoots")
        XCTAssertLessThan(scales.max()!, 1.25, "but not wildly")
        XCTAssertEqual(scales.last!, 1, accuracy: 0.0001)
    }

    func testBlurEntranceSharpensOverTime() {
        func blur(_ position: TimeInterval) -> Float { current(animate(position, entrance: .blur).animated)[0].blur }
        XCTAssertEqual(blur(1.0), 1, accuracy: 0.001)
        XCTAssertGreaterThan(blur(1.0), blur(1.3))
        XCTAssertGreaterThan(blur(1.3), blur(1.7))
        XCTAssertEqual(blur(2.1), 0)
    }

    func testCascadeStartsWordsInOrder() {
        // At 0.25 s the first words are well underway and the last has not started.
        let words = current(animate(1.25, entrance: .cascade).animated)
        let opacities = words.map(\.opacity)
        XCTAssertEqual(opacities.count, 4)
        XCTAssertGreaterThan(opacities[0], opacities[1])
        XCTAssertGreaterThan(opacities[1], opacities[2])
        XCTAssertGreaterThan(opacities[2], opacities[3])
        XCTAssertEqual(opacities[3], 0, "the last word has not begun")
        // Words further back are also lower on the screen: still rising into place.
        let plain = current(animate(1.25, entrance: .cascade).plain)
        XCTAssertGreaterThan(words[2].center.y - plain[2].center.y, words[0].center.y - plain[0].center.y)
    }

    func testGlitchJittersThenSettlesForGood() {
        let start = animate(1.0, entrance: .glitch)
        XCTAssertNotEqual(current(start.animated)[0].center.x, current(start.plain)[0].center.x)
        // After the first third the item is exactly the style's own.
        for position in [1.4, 1.6, 2.0] {
            let r = animate(position, entrance: .glitch)
            XCTAssertEqual(r.animated, r.plain, "settled at \(position)")
        }
        // Jitter shrinks toward the end of the burst.
        let early = abs(current(animate(1.02, entrance: .glitch).animated)[0].center.x - current(animate(1.02, entrance: .glitch).plain)[0].center.x)
        let late = abs(current(animate(1.3, entrance: .glitch).animated)[0].center.x - current(animate(1.3, entrance: .glitch).plain)[0].center.x)
        XCTAssertGreaterThan(early, late)
    }

    func testOnlyTheCurrentLineIsAnimated() {
        for kind in animated {
            let r = animate(1.0, entrance: kind, exit: .shrink)
            let previewPlain = r.plain.filter { $0.lineIndex == 1 }
            XCTAssertFalse(previewPlain.isEmpty, "the next-line preview exists")
            XCTAssertEqual(r.animated.filter { $0.lineIndex == 1 }, previewPlain, "\(kind) must not touch the preview")
        }
    }

    func testItemsWithoutALineIndexAreUntouched() {
        let loose = DrawItem(text: "x", font: FontSpec(size: 40), center: CGPoint(x: 10, y: 10), size: CGSize(width: 20, height: 40),
                             baseColor: .white, highlightColor: .white, glowColor: .white, glow: 0, progress: 0, opacity: 1)
        var config = OverlayConfig()
        config.entrance = .zoomIn
        XCTAssertEqual(Animator.apply([loose], frame: frame(1.0), config: config), [loose])
    }

    func testNothingAnimatesBeforeTheFirstLine() {
        var config = OverlayConfig()
        config.entrance = .rise
        let items = KaraokeLineStyle().layout(frame(0.5), viewport: viewport, config: config, measurer: measurer)
        XCTAssertEqual(Animator.apply(items, frame: frame(0.5), config: config), items)
    }

    func testStaggerOnlyAffectsCascade() {
        func opacities(_ kind: EntranceAnimation, stagger: Double) -> [Float] {
            current(animate(1.25, entrance: kind, tweak: { $0.entranceStagger = stagger }).animated).map(\.opacity)
        }
        XCTAssertEqual(opacities(.rise, stagger: 0), opacities(.rise, stagger: 0.5), "a rise ignores stagger")
        XCTAssertNotEqual(opacities(.cascade, stagger: 0), opacities(.cascade, stagger: 0.5))
    }

    func testZeroDurationFinishesImmediately() {
        for kind in animated {
            let r = animate(1.0, entrance: kind, tweak: { $0.entranceDuration = 0 })
            XCTAssertEqual(r.animated, r.plain, "\(kind)")
        }
    }
}

final class AnimatorExitTests: XCTestCase {
    private var exitMid: TimeInterval {
        let c = OverlayConfig()
        return document.lines[0].sungEnd + c.lingerAfterSung + c.fadeOutDuration / 2
    }
    private var exitStart: TimeInterval { document.lines[0].sungEnd + OverlayConfig().lingerAfterSung }

    func testNothingHappensBeforeTheLineStartsLeaving() {
        for kind in [ExitAnimation.rise, .shrink, .blur] {
            let r = animate(exitStart - 0.1, exit: kind)
            XCTAssertEqual(r.animated, r.plain, "\(kind)")
        }
    }

    func testRiseFloatsUp() {
        let r = animate(exitMid, exit: .rise)
        XCTAssertLessThan(current(r.animated)[0].center.y, current(r.plain)[0].center.y)
    }

    func testShrinkScalesDown() {
        let r = animate(exitMid, exit: .shrink)
        XCTAssertLessThan(current(r.animated)[0].scale, current(r.plain)[0].scale)
        XCTAssertGreaterThan(current(r.animated)[0].scale, 0.8)
    }

    func testDefocusBlurs() {
        let r = animate(exitMid, exit: .blur)
        XCTAssertGreaterThan(current(r.animated)[0].blur, 0.2)
        let later = animate(exitStart + OverlayConfig().fadeOutDuration * 0.9, exit: .blur)
        XCTAssertGreaterThan(current(later.animated)[0].blur, current(r.animated)[0].blur)
    }

    func testExitIsMonotonic() {
        let ys = stride(from: exitStart, through: exitStart + 0.75, by: 0.05).map { current(animate($0, exit: .rise).animated)[0].center.y }
        for (a, b) in zip(ys, ys.dropFirst()) { XCTAssertLessThanOrEqual(b, a + 1e-9) }
    }

    func testExitOnlyTouchesTheCurrentLine() {
        for kind in [ExitAnimation.rise, .shrink, .blur] {
            let r = animate(exitMid, exit: kind)
            let previewPlain = r.plain.filter { $0.lineIndex == 1 }
            XCTAssertFalse(previewPlain.isEmpty)
            XCTAssertEqual(r.animated.filter { $0.lineIndex == 1 }, previewPlain, "\(kind)")
        }
    }

    func testEntranceAndExitCompose() {
        // Long after the entrance, only the exit shows.
        let both = animate(exitMid, entrance: .zoomIn, exit: .rise)
        let exitOnly = animate(exitMid, exit: .rise)
        XCTAssertEqual(both.animated, exitOnly.animated)
    }
}

final class StyleTaggingTests: XCTestCase {
    func testEveryStyleTagsItsItemsWithTheirLine() {
        for info in LyricStyles.all {
            for position in [1.5, 2.2, 3.0] {
                let f = frame(position)
                let items = LyricStyles.style(id: info.id).layout(f, viewport: viewport, config: OverlayConfig(), measurer: measurer)
                XCTAssertFalse(items.isEmpty, "\(info.id) at \(position)")
                for item in items {
                    let index = try? XCTUnwrap(item.lineIndex, "\(info.id) left an item without a line index")
                    if let index { XCTAssertTrue(document.lines.indices.contains(index), "\(info.id)") }
                }
                let mine = items.filter { $0.lineIndex == f.cursor.lineIndex }
                XCTAssertFalse(mine.isEmpty, "\(info.id) must tag the current line's items")
                for item in mine {
                    XCTAssertTrue((0..<document.lines[0].words.count).contains(item.wordIndex), "\(info.id) word index \(item.wordIndex)")
                }
            }
        }
    }

    func testWholeLineItemsUseWordIndexZero() {
        // The preview is one item for the whole next line.
        let items = KaraokeLineStyle().layout(frame(2.0), viewport: viewport, config: OverlayConfig(), measurer: measurer)
        let preview = items.filter { $0.lineIndex == 1 }
        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview[0].wordIndex, 0)
    }

    func testKaraokeWordsAreNumberedInReadingOrder() {
        let items = KaraokeLineStyle().layout(frame(2.0), viewport: viewport, config: OverlayConfig(), measurer: measurer)
        XCTAssertEqual(current(items).map(\.wordIndex), [0, 1, 2, 3])
        XCTAssertEqual(current(items).map(\.text), ["one", "two", "three", "four"])
    }
}

final class LyricsPipelineTests: XCTestCase {
    private func pipeline(_ position: TimeInterval, style: LyricStyle = KaraokeLineStyle(),
                          tweak: (inout OverlayConfig) -> Void = { _ in }) -> [DrawItem] {
        var config = OverlayConfig()
        tweak(&config)
        return LyricsPipeline.items(style: style, frame: frame(position), viewport: viewport, config: config, measurer: measurer)
    }

    func testDefaultConfigReproducesThePlainStyleOutputExactly() {
        for info in LyricStyles.all {
            let style = LyricStyles.style(id: info.id)
            for position in [0.5, 1.0, 1.2, 2.0, 4.0, 6.0, 9.5, 10.2] {
                let plain = style.layout(frame(position), viewport: viewport, config: OverlayConfig(), measurer: measurer)
                XCTAssertEqual(pipeline(position, style: style), plain, "\(info.id) at \(position)")
            }
        }
    }

    func testNoneEntranceMakesTheFirstFrameFullyOpaque() {
        let withFade = current(pipeline(1.0))
        XCTAssertTrue(withFade.isEmpty || withFade[0].opacity < 0.01, "the default fades in from nothing")
        let none = current(pipeline(1.0) { $0.entrance = .none })
        XCTAssertFalse(none.isEmpty)
        XCTAssertTrue(none.allSatisfy { $0.opacity == 1 })
    }

    func testNoneExitKeepsTheLineUntilTheNextOneReplacesIt() {
        // Well past the fade-out: by default the line is gone, with exit none it stays.
        XCTAssertTrue(current(pipeline(8.0)).isEmpty)
        let none = current(pipeline(8.0) { $0.exit = .none })
        XCTAssertEqual(none.count, 4)
        XCTAssertTrue(none.allSatisfy { $0.opacity == 1 })
        // And the next line still takes over at its start.
        XCTAssertTrue(current(pipeline(10.5) { $0.exit = .none }).isEmpty)
    }

    func testAnimationsAreAppliedThroughThePipeline() {
        let base = current(pipeline(1.1) { $0.entrance = .fade })
        let rise = current(pipeline(1.1) { $0.entrance = .rise })
        XCTAssertFalse(rise.isEmpty)
        XCTAssertGreaterThan(rise[0].center.y, base[0].center.y, "rise starts lower than the plain layout")
    }

    func testPipelineDoesNotMutateTheCallersConfig() {
        var config = OverlayConfig()
        config.entrance = .none
        config.exit = .none
        let before = config
        _ = LyricsPipeline.items(style: KaraokeLineStyle(), frame: frame(1.0), viewport: viewport, config: config, measurer: measurer)
        XCTAssertEqual(config, before)
    }

    func testEveryStyleWorksWithEveryEntranceAndExit() {
        for info in LyricStyles.all {
            for entrance in EntranceAnimation.allCases {
                for exit in ExitAnimation.allCases {
                    for position in [1.0, 1.3, 2.5, 5.5, 6.0] {
                        let items = pipeline(position, style: LyricStyles.style(id: info.id)) { $0.entrance = entrance; $0.exit = exit }
                        for item in items {
                            XCTAssertTrue(item.opacity >= 0 && item.opacity <= 1.0001, "\(info.id) \(entrance) \(exit) opacity \(item.opacity)")
                            XCTAssertTrue(item.blur >= 0 && item.blur <= 1.0001)
                            XCTAssertTrue(item.center.x.isFinite && item.center.y.isFinite && item.scale > 0 && item.scale.isFinite)
                        }
                    }
                }
            }
        }
    }
}

final class AnimationKindsTests: XCTestCase {
    func testTitlesAreUniqueAndNonEmpty() {
        let e = EntranceAnimation.allCases.map(\.title), x = ExitAnimation.allCases.map(\.title)
        XCTAssertEqual(Set(e).count, e.count)
        XCTAssertEqual(Set(x).count, x.count)
        XCTAssertTrue((e + x).allSatisfy { !$0.isEmpty })
    }

    func testConfigDefaultsKeepTodaysLook() {
        let c = OverlayConfig()
        XCTAssertEqual(c.entrance, .fade)
        XCTAssertEqual(c.exit, .fade)
    }

    func testConfigRoundTripAndTolerantDecoding() throws {
        var c = OverlayConfig()
        c.entrance = .cascade
        c.exit = .blur
        c.entranceDuration = 0.9
        c.entranceStagger = 0.12
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(OverlayConfig.self, from: data), c)

        // An unknown animation name (from a newer version) falls back instead of failing the whole file.
        let decoded = try JSONDecoder().decode(OverlayConfig.self, from: Data(#"{"entrance": "teleport", "glow": 0.2}"#.utf8))
        XCTAssertEqual(decoded.entrance, .fade)
        XCTAssertEqual(decoded.glow, 0.2, accuracy: 1e-6)
    }
}
