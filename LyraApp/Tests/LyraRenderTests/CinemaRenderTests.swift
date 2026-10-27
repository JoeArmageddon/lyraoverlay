import XCTest
import CoreGraphics
import LyraCore
@testable import LyraRender

/// Premultiplied BGRA pixels of an offscreen render, so tests can look at exact values.
private struct Pixels {
    let width: Int, height: Int
    private let data: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = bytes
    }

    var bytes: [UInt8] { data }
    func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * width + x) * 4
        return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]), Int(data[i + 3]))
    }
    func alpha(_ x: Int, _ y: Int) -> Int { rgba(x, y).a }
    /// Brightness (0...255) of the pixel if it were drawn over a plain white background.
    func overWhite(_ x: Int, _ y: Int) -> Double {
        let p = rgba(x, y)
        return Double(p.r + p.g + p.b) / 3 + Double(255 - p.a)
    }
}

private func renderer() throws -> MetalRenderer { try metalRendererOrSkip() }

private func settings(_ mutate: (inout CinemaSettings) -> Void = { _ in }) -> CinemaSettings {
    var s = CinemaSettings()
    s.enabled = true
    s.vignette = 0
    s.grain = 0
    s.flare = 0
    mutate(&s)
    return s
}

private func frame(_ s: CinemaSettings, _ size: CGSize, beat: Float = 0, emphasis: CGPoint? = nil, time: Double = 0) -> CinemaFrame? {
    CinemaEffect.frame(settings: s, viewport: size, beat: beat, bass: 0, emphasisCenter: emphasis, time: time)
}

private let size = CGSize(width: 800, height: 500)

final class CinemaBarRenderTests: XCTestCase {
    func testBarRowsAreExactlyBlackAndOpaqueAndThePictureStaysEmpty() throws {
        let cinema = try XCTUnwrap(frame(settings { $0.letterbox = .cinemascope }, size))
        let image = try XCTUnwrap(renderer().renderOffscreen([], cinema: cinema, size: size, scale: 1))
        let px = Pixels(image)
        let bar = Int((cinema.barFraction * 500).rounded())
        XCTAssertGreaterThan(bar, 60)

        for y in [0, 1, bar / 2, bar - 1, 500 - bar, 500 - bar + 1, 499] {
            for x in [0, 1, 400, 798, 799] {
                let p = px.rgba(x, y)
                XCTAssertEqual([p.r, p.g, p.b, p.a], [0, 0, 0, 255], "bar pixel (\(x),\(y)) must be solid black")
            }
        }
        for y in [bar, bar + 1, 250, 499 - bar - 1, 499 - bar] {
            XCTAssertEqual(px.alpha(400, y), 0, "picture row \(y) has nothing drawn, so it stays transparent")
        }
    }

    func testBarsMatchTheRatio() throws {
        for ratio in [LetterboxRatio.cinemascope, .flat, .wide] {
            let cinema = try XCTUnwrap(frame(settings { $0.letterbox = ratio }, size))
            let px = Pixels(try XCTUnwrap(renderer().renderOffscreen([], cinema: cinema, size: size, scale: 1)))
            var opaqueRows = 0
            for y in 0..<500 where px.alpha(400, y) == 255 { opaqueRows += 1 }
            let picture = 500 - opaqueRows
            XCTAssertEqual(Double(800) / Double(picture), ratio.aspect!, accuracy: 0.03, "\(ratio): picture is \(picture) rows tall")
            XCTAssertEqual(opaqueRows % 2, 0, "the same bar on top and bottom")
        }
    }

    func testBarsScaleWithTheRetinaFactor() throws {
        let cinema = try XCTUnwrap(frame(settings { $0.letterbox = .cinemascope }, size))
        let px = Pixels(try XCTUnwrap(renderer().renderOffscreen([], cinema: cinema, size: size, scale: 2)))
        XCTAssertEqual(px.height, 1000)
        let bar1 = Int((cinema.barFraction * 1000).rounded())
        XCTAssertEqual(px.alpha(800, bar1 - 1), 255)
        XCTAssertEqual(px.alpha(800, bar1), 0)
    }

    func testTextDrawsInsideThePictureNotUnderTheBars() throws {
        let s = settings { $0.letterbox = .cinemascope }
        let region = PlayerFrameBuilder.lyricRegion(cinema: s, viewport: size)
        let item = DrawItem(text: "MMMM", font: FontSpec(size: 80, weight: 0.5), center: CGPoint(x: region.width / 2, y: region.height / 2),
                            size: CGSize(width: 300, height: 90), baseColor: .white, highlightColor: .white, glowColor: .white,
                            glow: 0, progress: 1, opacity: 1)
        let items = PlayerFrameBuilder.shifted([item], by: region.origin)
        let cinema = try XCTUnwrap(frame(s, size))
        let px = Pixels(try XCTUnwrap(renderer().renderOffscreen(items, cinema: cinema, size: size, scale: 1)))

        var textRows = Set<Int>()
        for y in 0..<500 { for x in stride(from: 200, to: 600, by: 2) where px.rgba(x, y).r > 128 && px.rgba(x, y).a == 255 { textRows.insert(y) } }
        XCTAssertFalse(textRows.isEmpty, "the text is visible")
        let bar = Int((cinema.barFraction * 500).rounded())
        XCTAssertGreaterThanOrEqual(textRows.min()!, bar, "no text above the picture")
        XCTAssertLessThan(textRows.max()!, 500 - bar, "no text below the picture")
        XCTAssertEqual(Double(textRows.min()! + textRows.max()!) / 2, 250, accuracy: 8, "centered in the picture")
    }

    func testTheBorderHugsThePictureWhenThereAreBars() throws {
        let lights = LightParams(primary: RGBA(0.2, 0.5, 1), secondary: RGBA(1, 0.3, 0.8), thickness: 24, cornerRadius: 0, intensity: 1, phase: 0)
        let cinema = try XCTUnwrap(frame(settings { $0.letterbox = .cinemascope }, size))
        let px = Pixels(try XCTUnwrap(renderer().renderOffscreen([], lights: lights, cinema: cinema, size: size, scale: 1)))
        let bar = Int((cinema.barFraction * 500).rounded())

        XCTAssertGreaterThan(px.alpha(400, bar + 1), 150, "glow sits on the picture's top edge, right under the bar")
        XCTAssertGreaterThan(px.alpha(400, 499 - bar - 1), 150, "and on its bottom edge")
        XCTAssertGreaterThan(px.alpha(1, 250), 150, "and its sides")
        XCTAssertLessThan(px.alpha(400, 250), 3, "the middle stays clear")
        XCTAssertEqual(px.rgba(400, bar - 1).a, 255)
        XCTAssertEqual(px.rgba(400, bar - 1).r, 0, "the bar itself is still pure black")
    }
}

final class CinemaVignetteGrainRenderTests: XCTestCase {
    func testCornersAreDarkerThanTheCentre() throws {
        let cinema = try XCTUnwrap(frame(settings { $0.letterbox = .off; $0.vignette = 1 }, size))
        let px = Pixels(try XCTUnwrap(renderer().renderOffscreen([], cinema: cinema, size: size, scale: 1)))
        XCTAssertGreaterThan(px.alpha(2, 2), 150, "the corner is strongly darkened")
        XCTAssertLessThan(px.alpha(400, 250), 3)

        // Over a white background: the centre stays white, every corner goes dark.
        XCTAssertGreaterThan(px.overWhite(400, 250), 250, "centre is untouched")
        for (x, y) in [(1, 1), (798, 1), (1, 498), (798, 498)] {
            XCTAssertLessThan(px.overWhite(x, y), 110, "corner (\(x),\(y)) is dark over white")
        }
    }

    func testVignetteGrowsSmoothlyOutwardWithoutARing() throws {
        let cinema = try XCTUnwrap(frame(settings { $0.letterbox = .off; $0.vignette = 1 }, size))
        let px = Pixels(try XCTUnwrap(renderer().renderOffscreen([], cinema: cinema, size: size, scale: 1)))
        var previous = -1
        var biggestJump = 0
        for t in 0...100 {   // from the centre to the corner along the diagonal
            let x = 400 + (399 * t) / 100, y = 250 + (249 * t) / 100
            let a = px.alpha(x, y)
            XCTAssertGreaterThanOrEqual(a, previous - 2, "never gets lighter going outward (t=\(t))")
            if previous >= 0 { biggestJump = max(biggestJump, a - previous) }
            previous = a
        }
        XCTAssertLessThan(biggestJump, 12, "no visible step: the gradient is smooth")
    }

    func testVignetteStrengthScalesAndZeroDrawsNothing() throws {
        let r = try renderer()
        func corner(_ v: Double) throws -> Int {
            let c = try XCTUnwrap(frame(settings { $0.letterbox = .off; $0.vignette = v }, size))
            return Pixels(try XCTUnwrap(r.renderOffscreen([], cinema: c, size: size, scale: 1))).alpha(2, 2)
        }
        let strong = try corner(1), soft = try corner(0.3), none = try corner(0)
        XCTAssertGreaterThan(strong, soft)
        XCTAssertGreaterThan(soft, 20)
        XCTAssertEqual(none, 0)
    }

    func testGrainIsFineBothLightAndDarkAndRepeatsPerSeed() throws {
        let r = try renderer()
        func render(time: Double) throws -> Pixels {
            let c = try XCTUnwrap(frame(settings { $0.letterbox = .off; $0.grain = 1 }, size, time: time))
            return Pixels(try XCTUnwrap(r.renderOffscreen([], cinema: c, size: size, scale: 1)))
        }
        let a = try render(time: 5.00), sameFrame = try render(time: 5.00 + 0.5 / 24), later = try render(time: 5.00 + 2.2 / 24)
        XCTAssertEqual(a.bytes, sameFrame.bytes, "one film frame: identical grain")
        XCTAssertNotEqual(a.bytes, later.bytes, "the next frames: new grain")

        var differing = 0, light = 0, dark = 0, total = 0
        for y in stride(from: 0, to: 500, by: 3) {
            for x in stride(from: 0, to: 800, by: 3) {
                total += 1
                let p = a.rgba(x, y), q = later.rgba(x, y)
                if p.a != q.a || p.r != q.r { differing += 1 }
                if p.a > 0 { if p.r > 0 { light += 1 } else { dark += 1 } }
            }
        }
        XCTAssertGreaterThan(Double(differing) / Double(total), 0.4, "a new frame changes most of the pattern")
        XCTAssertGreaterThan(light, total / 6, "some grain lightens")
        XCTAssertGreaterThan(dark, total / 6, "some grain darkens")

        // Fine, not blocky: neighbouring pixels are not mostly identical.
        var sameAsNeighbour = 0, pairs = 0
        for y in stride(from: 0, to: 500, by: 5) {
            for x in stride(from: 0, to: 798, by: 5) {
                pairs += 1
                if a.rgba(x, y) == a.rgba(x + 1, y) { sameAsNeighbour += 1 }
            }
        }
        XCTAssertLessThan(Double(sameAsNeighbour) / Double(pairs), 0.5, "grain is per pixel at 1x, not coarse blocks")
    }

    func testGrainIsSubtleAtTheDefaultStrength() throws {
        let c = try XCTUnwrap(frame(settings { $0.letterbox = .off; $0.grain = 0.18 }, size))
        let px = Pixels(try XCTUnwrap(renderer().renderOffscreen([], cinema: c, size: size, scale: 1)))
        var peak = 0
        for y in stride(from: 0, to: 500, by: 2) { for x in stride(from: 0, to: 800, by: 2) { peak = max(peak, px.alpha(x, y)) } }
        XCTAssertLessThan(peak, 60, "default grain never shows harsh specks (alpha \(peak) of 255)")
        XCTAssertGreaterThan(peak, 4, "but it is there")
    }
}

final class CinemaFlareRenderTests: XCTestCase {
    private func render(beat: Float, emphasis: CGPoint?) throws -> Pixels {
        let c = try XCTUnwrap(frame(settings { $0.letterbox = .off; $0.flare = 1 }, size, beat: beat, emphasis: emphasis))
        return Pixels(try XCTUnwrap(try renderer().renderOffscreen([], cinema: c, size: size, scale: 1)))
    }

    func testFlareBrightensTheStreakRowMoreOnABeat() throws {
        let centre = CGPoint(x: 400, y: 250)
        let hit = try render(beat: 1, emphasis: centre), rest = try render(beat: 0, emphasis: centre)
        let row = 250
        for x in [400, 330, 470, 250, 550] {
            XCTAssertGreaterThan(hit.rgba(x, row).a, rest.rgba(x, row).a, "x=\(x): brighter on the beat")
        }
        XCTAssertGreaterThan(hit.rgba(400, row).a, 200, "the heart of the streak is strong on a beat")
        XCTAssertGreaterThan(rest.rgba(400, row).a, 5, "and there is a faint resting glow between beats")
    }

    func testFlareStaysOnItsRowAndFadesAtTheEnds() throws {
        let hit = try render(beat: 1, emphasis: CGPoint(x: 400, y: 250))
        for y in [250 - 80, 250 + 80, 100, 400] { XCTAssertLessThan(hit.alpha(400, y), 3, "row \(y) is clear of the streak") }
        XCTAssertGreaterThan(hit.alpha(400, 252), 100, "close to the streak it is still bright")
        XCTAssertGreaterThan(hit.alpha(400, 250), hit.alpha(400, 262), "falls off away from the line")
        XCTAssertGreaterThan(hit.alpha(400, 250), hit.alpha(600, 250), "and along it")
        XCTAssertEqual(hit.alpha(5, 250), 0, "the far ends are dark")
    }

    func testFlareIsBluishWhite() throws {
        let hit = try render(beat: 1, emphasis: CGPoint(x: 400, y: 250))
        let p = hit.rgba(300, 250)
        XCTAssertGreaterThan(p.r, 60, "bright, not just blue")
        XCTAssertGreaterThan(p.b, p.r, "tinted slightly blue")
    }

    func testFlareFollowsTheEmphasisPoint() throws {
        let hit = try render(beat: 1, emphasis: CGPoint(x: 200, y: 120))
        XCTAssertGreaterThan(hit.alpha(200, 120), 200)
        XCTAssertLessThan(hit.alpha(200, 250), 3, "the old centre row is dark now")
        XCTAssertGreaterThan(hit.alpha(150, 120), hit.alpha(150, 140))
    }

    func testFlareIsAddedToTheLightAlreadyThere() throws {
        // On top of a bright pixel an additive streak must not darken it.
        let c = try XCTUnwrap(frame(settings { $0.letterbox = .off; $0.flare = 1 }, size, beat: 1, emphasis: CGPoint(x: 400, y: 250)))
        let lights = LightParams(primary: RGBA(1, 0.2, 0.2), secondary: RGBA(1, 0.2, 0.2), thickness: 400, cornerRadius: 0, intensity: 1, phase: 0)
        let with = Pixels(try XCTUnwrap(renderer().renderOffscreen([], lights: lights, cinema: c, size: size, scale: 1)))
        let without = Pixels(try XCTUnwrap(renderer().renderOffscreen([], lights: lights, size: size, scale: 1)))
        XCTAssertGreaterThanOrEqual(with.rgba(400, 250).g, without.rgba(400, 250).g)
        XCTAssertGreaterThanOrEqual(with.rgba(400, 250).b, without.rgba(400, 250).b)
        XCTAssertGreaterThan(with.rgba(400, 250).g + with.rgba(400, 250).b, without.rgba(400, 250).g + without.rgba(400, 250).b)
    }
}

final class CinemaIdentityTests: XCTestCase {
    private func sampleItems() -> [DrawItem] {
        let doc = LRCParser.parse("[00:00.00]Rain on the empty avenue tonight\n[00:08.00]Next line here", source: "t")!
        let frame = LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: 2.5), position: 2.5)
        return KaraokeLineStyle().layout(frame, viewport: size, config: OverlayConfig(), measurer: CoreTextMeasurer())
    }

    func testDisabledCinemaGivesNoFrameAndAnIdenticalImage() throws {
        var off = CinemaSettings()
        off.enabled = false
        XCTAssertNil(CinemaEffect.frame(settings: off, viewport: size, beat: 1, bass: 1, emphasisCenter: nil, time: 3))

        let r = try renderer()
        let lights = LightParams(primary: RGBA(0.2, 0.5, 1), secondary: RGBA(1, 0.3, 0.8), thickness: 20, cornerRadius: 12, intensity: 0.8, phase: 0.1)
        let items = sampleItems()
        let plain = Pixels(try XCTUnwrap(r.renderOffscreen(items, lights: lights, size: size, scale: 2)))
        let withNil = Pixels(try XCTUnwrap(r.renderOffscreen(items, lights: lights, cinema: nil, size: size, scale: 2)))
        XCTAssertEqual(plain.bytes, withNil.bytes, "bit for bit")
    }

    func testAFrameThatAsksForNothingDrawsNothing() throws {
        let nothing = CinemaFrame(barFraction: 0, vignette: 0, grain: 0, grainSeed: 3, flare: 0,
                                  flareCenter: .zero, flareHalfWidth: 100)
        XCTAssertEqual(MetalRenderer.cinemaPasses(for: nothing), [])
        let r = try renderer()
        let items = sampleItems()
        let plain = Pixels(try XCTUnwrap(r.renderOffscreen(items, size: size, scale: 1)))
        let withEmpty = Pixels(try XCTUnwrap(r.renderOffscreen(items, cinema: nothing, size: size, scale: 1)))
        XCTAssertEqual(plain.bytes, withEmpty.bytes)

        // Cinema "enabled" with every effect at zero and no bars is also a no-op.
        var s = CinemaSettings()
        s.enabled = true; s.letterbox = .off; s.vignette = 0; s.grain = 0; s.flare = 0
        let quiet = try XCTUnwrap(frame(s, size))
        XCTAssertEqual(MetalRenderer.cinemaPasses(for: quiet), [])
    }

    func testPassesAreChosenAndOrdered() {
        var f = CinemaFrame(barFraction: 0.1, vignette: 0.5, grain: 0.2, grainSeed: 1, flare: 0.6, flareCenter: .zero, flareHalfWidth: 50)
        XCTAssertEqual(MetalRenderer.cinemaPasses(for: f), [.flare, .vignette, .grain, .bars], "bars are drawn last, over everything")
        f.flare = 0; f.grain = 0
        XCTAssertEqual(MetalRenderer.cinemaPasses(for: f), [.vignette, .bars])
        f.vignette = 0
        XCTAssertEqual(MetalRenderer.cinemaPasses(for: f), [.bars])
    }

    func testUniformLayoutMatchesTheShader() {
        // 76 bytes of fields plus a pad, in an 8-byte aligned struct.
        XCTAssertEqual(MemoryLayout<MetalRenderer.CinemaUniforms>.stride, 80)
    }

    func testExistingUniformsAreUntouched() {
        XCTAssertEqual(MemoryLayout<MetalRenderer.Uniforms>.stride, 112)
        XCTAssertEqual(MemoryLayout<MetalRenderer.RimUniforms>.stride, 80)
    }
}

final class PlayerCinemaBuilderTests: XCTestCase {
    private func item(y: CGFloat, emphasis: Bool = false, opacity: Float = 1) -> DrawItem {
        DrawItem(text: "x", font: FontSpec(size: 20), center: CGPoint(x: 10, y: y), size: CGSize(width: 10, height: 10),
                 baseColor: .white, highlightColor: .white, glowColor: .white, glow: 0, progress: 1, opacity: opacity, isEmphasis: emphasis)
    }

    func testRegionIsTheWholeViewWithCinemaOffAndThePictureWithItOn() {
        let view = CGSize(width: 1200, height: 800)
        var s = CinemaSettings()
        XCTAssertEqual(PlayerFrameBuilder.lyricRegion(cinema: s, viewport: view), CGRect(origin: .zero, size: view))
        s.enabled = true
        let region = PlayerFrameBuilder.lyricRegion(cinema: s, viewport: view)
        XCTAssertEqual(region.width, 1200)
        XCTAssertEqual(region.width / region.height, 2.39, accuracy: 1e-9)
        XCTAssertEqual(region.midY, 400, accuracy: 1e-9)
    }

    func testShiftingByNothingReturnsTheSameItemsAndShiftingMovesOnlyY() {
        let items = [item(y: 100), item(y: 200)]
        XCTAssertEqual(PlayerFrameBuilder.shifted(items, by: .zero), items)
        let moved = PlayerFrameBuilder.shifted(items, by: CGPoint(x: 0, y: 50))
        XCTAssertEqual(moved.map(\.center.y), [150, 250])
        XCTAssertEqual(moved.map(\.center.x), [10, 10])
        XCTAssertEqual(moved.map(\.size), items.map(\.size))
    }

    func testCinemaOffLayoutIsIdenticalToTheStyleDirectly() {
        // The path the player takes with cinema off: region = whole view, no shift, no features.
        let view = CGSize(width: 1000, height: 600)
        let doc = LRCParser.parse("[00:00.00]A short line of words here\n[00:09.00]more", source: "t")!
        let cursor = LyricsCursor(document: doc).state(at: 2)
        let config = PlayerFrameBuilder.lyricConfig(base: OverlayConfig(), albumPalette: nil, useArtworkColors: false, viewportWidth: view.width, lyricsScale: 1)
        let measurer = CoreTextMeasurer()

        let direct = KaraokeLineStyle().layout(LyricsFrame(lines: doc.lines, cursor: cursor, position: 2), viewport: view, config: config, measurer: measurer)

        let region = PlayerFrameBuilder.lyricRegion(cinema: CinemaSettings(), viewport: view)
        let frame = PlayerFrameBuilder.lyricsFrame(lines: doc.lines, cursor: cursor, position: 2, features: nil)
        let viaPlayer = PlayerFrameBuilder.shifted(KaraokeLineStyle().layout(frame, viewport: region.size, config: config, measurer: measurer), by: region.origin)
        XCTAssertEqual(viaPlayer, direct, "bit for bit identical with cinema off")
    }

    func testFramePassesTheMusicThroughOrZeros() {
        let doc = LRCParser.parse("[00:00.00]hi", source: "t")!
        let cursor = LyricsCursor(document: doc).state(at: 0.5)
        let music = AudioFeatures(level: 0.5, bass: 0.7, mid: 0.2, treble: 0.1, beat: 0.9, bpm: 120, brightness: 0.3, energy: 0.5)
        let withAudio = PlayerFrameBuilder.lyricsFrame(lines: doc.lines, cursor: cursor, position: 0.5, features: music)
        XCTAssertEqual(withAudio.beat, 0.9, accuracy: 1e-6)
        XCTAssertEqual(withAudio.bass, 0.7, accuracy: 1e-6)
        let silent = PlayerFrameBuilder.lyricsFrame(lines: doc.lines, cursor: cursor, position: 0.5, features: nil)
        XCTAssertEqual(silent.beat, 0)
        XCTAssertEqual(silent.bass, 0)
    }

    func testEmphasisCenterIgnoresInvisibleAndUnmarkedWords() {
        XCTAssertNil(PlayerFrameBuilder.emphasisCenter(in: [item(y: 10), item(y: 20)]))
        XCTAssertEqual(PlayerFrameBuilder.emphasisCenter(in: [item(y: 10), item(y: 20, emphasis: true)])?.y, 20)
        XCTAssertNil(PlayerFrameBuilder.emphasisCenter(in: [item(y: 20, emphasis: true, opacity: 0.01)]), "still fading in: no flare yet")
        XCTAssertNil(PlayerFrameBuilder.emphasisCenter(in: []))
    }
}
