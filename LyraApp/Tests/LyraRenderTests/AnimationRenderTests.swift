import XCTest
import LyraCore
@testable import LyraRender

final class AnimationRenderTests: XCTestCase {
    private let size = CGSize(width: 800, height: 300)

    private func renderer() throws -> MetalRenderer {
        try metalRendererOrSkip()
    }

    /// Premultiplied BGRA bytes of a 1x render.
    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private struct Stats { var peak: Int; var extent: Int; var total: Int }

    /// Highest alpha, horizontal extent of everything above a faint threshold, and summed alpha.
    private func stats(_ image: CGImage, threshold: Int = 8) -> Stats {
        let w = image.width, h = image.height
        let data = pixels(image)
        var peak = 0, total = 0, minX = w, maxX = -1
        for y in 0..<h {
            for x in 0..<w {
                let a = Int(data[(y * w + x) * 4 + 3])
                total += a
                peak = max(peak, a)
                if a > threshold { minX = min(minX, x); maxX = max(maxX, x) }
            }
        }
        return Stats(peak: peak, extent: maxX >= minX ? maxX - minX + 1 : 0, total: total)
    }

    /// Thin strokes on purpose: a bold glyph has stems and junctions wider than the blur radius,
    /// so some of its pixels stay fully solid and the peak would not show the blur at all.
    private func word(blur: Float = 0, glow: Float = 0, shadow: Float = 0) -> DrawItem {
        DrawItem(text: "llll", font: FontSpec(size: 60, weight: 0), center: CGPoint(x: 400, y: 150), size: CGSize(width: 100, height: 80),
                 baseColor: .white, highlightColor: .white, glowColor: .white, glow: glow, progress: 1, opacity: 1,
                 shadow: shadow, blur: blur)
    }

    // MARK: - Blur

    func testBlurLowersThePeakAndSpreadsTheInk() throws {
        let r = try renderer()
        let sharp = stats(try XCTUnwrap(r.renderOffscreen([word(blur: 0)], size: size, scale: 1)))
        let soft = stats(try XCTUnwrap(r.renderOffscreen([word(blur: 1)], size: size, scale: 1)))
        XCTAssertGreaterThan(sharp.peak, 240)
        XCTAssertLessThan(soft.peak, sharp.peak - 40, "blurred glyphs are never as solid")
        XCTAssertGreaterThan(soft.extent, sharp.extent + 4, "and they bleed past the glyph edges")
    }

    func testBlurIsMonotonic() throws {
        let r = try renderer()
        let peaks = try [Float(0), 0.4, 0.8, 1].map { stats(try XCTUnwrap(r.renderOffscreen([word(blur: $0)], size: size, scale: 1))).peak }
        for (a, b) in zip(peaks, peaks.dropFirst()) { XCTAssertLessThan(b, a, "peaks \(peaks)") }
    }

    func testBlurZeroIsExactlyTheUnblurredRender() throws {
        let r = try renderer()
        let plain = DrawItem(text: "MMMM", font: FontSpec(size: 72, weight: 0.5), center: CGPoint(x: 400, y: 150), size: CGSize(width: 260, height: 90),
                             baseColor: .white, highlightColor: .white, glowColor: .white, glow: 0.6, progress: 1, opacity: 1, shadow: 0.5)
        XCTAssertEqual(plain.blur, 0, "the default is sharp")
        var zero = plain
        zero.blur = 0
        let a = pixels(try XCTUnwrap(r.renderOffscreen([plain], size: size, scale: 1)))
        let b = pixels(try XCTUnwrap(r.renderOffscreen([zero], size: size, scale: 1)))
        XCTAssertEqual(a, b)
    }

    func testATinyBlurIsAlmostInvisible() throws {
        // Continuity: the blurred path must meet the sharp one, not jump away from it.
        let r = try renderer()
        let sharp = stats(try XCTUnwrap(r.renderOffscreen([word(glow: 0.6, shadow: 0.5)], size: size, scale: 1)))
        let tiny = stats(try XCTUnwrap(r.renderOffscreen([word(blur: 0.01, glow: 0.6, shadow: 0.5)], size: size, scale: 1)))
        XCTAssertEqual(Double(tiny.total), Double(sharp.total), accuracy: Double(sharp.total) * 0.02)
        XCTAssertEqual(tiny.peak, sharp.peak, accuracy: 6)
    }

    func testBlurOutsideZeroToOneIsClamped() throws {
        let r = try renderer()
        let one = pixels(try XCTUnwrap(r.renderOffscreen([word(blur: 1)], size: size, scale: 1)))
        let big = pixels(try XCTUnwrap(r.renderOffscreen([word(blur: 7)], size: size, scale: 1)))
        let negative = pixels(try XCTUnwrap(r.renderOffscreen([word(blur: -3)], size: size, scale: 1)))
        let zero = pixels(try XCTUnwrap(r.renderOffscreen([word(blur: 0)], size: size, scale: 1)))
        XCTAssertEqual(one, big)
        XCTAssertEqual(negative, zero)
    }

    func testDefocusedTextDropsItsCrispShadowOutline() throws {
        // A hard dark outline around soft text would look wrong, so the halo fades with the blur.
        let r = try renderer()
        let withShadow = stats(try XCTUnwrap(r.renderOffscreen([word(blur: 1, shadow: 1)], size: size, scale: 1)))
        let without = stats(try XCTUnwrap(r.renderOffscreen([word(blur: 1, shadow: 0)], size: size, scale: 1)))
        XCTAssertEqual(Double(withShadow.total), Double(without.total), accuracy: Double(without.total) * 0.03)
    }

    func testShaderUniformsStayInLockstep() {
        // 108 bytes of fields (blur is the last) padded to the 16-byte alignment of the float4s.
        XCTAssertEqual(MemoryLayout<MetalRenderer.Uniforms>.stride, 112)
        XCTAssertEqual(MemoryLayout<MetalRenderer.Uniforms>.offset(of: \.blur), 108)
    }

    // MARK: - Through the pipeline

    private let lrc = "[00:01.00]one two three four\n[00:10.00]next line here"

    private func render(entrance: EntranceAnimation, exit: ExitAnimation = .fade, at position: TimeInterval,
                        tweak: (inout OverlayConfig) -> Void = { _ in }) throws -> CGImage {
        let doc = try XCTUnwrap(LRCParser.parse(lrc))
        var config = OverlayConfig()
        config.entrance = entrance
        config.exit = exit
        config.entranceDuration = 1.0
        config.anchorY = 0.5
        config.showNextLine = false
        config.font = FontSpec(size: 56, weight: 0.5)
        tweak(&config)
        let frame = LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: position), position: position)
        let items = LyricsPipeline.items(style: KaraokeLineStyle(), frame: frame, viewport: size, config: config, measurer: CoreTextMeasurer())
        return try XCTUnwrap(try renderer().renderOffscreen(items, size: size, scale: 1))
    }

    func testEveryEntranceLooksDifferentMidwayThanWhenFinished() throws {
        for kind in EntranceAnimation.allCases where kind != .none && kind != .fade {
            let mid = pixels(try render(entrance: kind, at: 1.3))
            let done = pixels(try render(entrance: kind, at: 3.0))
            XCTAssertNotEqual(mid, done, "\(kind)")
        }
    }

    func testAFinishedEntranceRendersExactlyLikeNoAnimation() throws {
        let plain = pixels(try render(entrance: .fade, at: 3.0))
        for kind in EntranceAnimation.allCases {
            XCTAssertEqual(pixels(try render(entrance: kind, at: 3.0)), plain, "\(kind) must leave no trace once finished")
        }
    }

    func testBlurEntranceStartsSofterThanItEnds() throws {
        let early = stats(try render(entrance: .blur, at: 1.05))
        let done = stats(try render(entrance: .blur, at: 3.0))
        XCTAssertGreaterThan(done.peak, early.peak)
    }

    func testDefocusExitIsSofterThanAPlainFadeAtTheSameMoment() throws {
        let doc = try XCTUnwrap(LRCParser.parse(lrc))
        let moment = doc.lines[0].sungEnd + OverlayConfig().lingerAfterSung + 0.5   // most of the way out
        // Light strokes, so the blur shows in the peak (see `word`); both renders fade identically.
        let light: (inout OverlayConfig) -> Void = { $0.font = FontSpec(size: 56, weight: -0.5) }
        let faded = stats(try render(entrance: .fade, exit: .fade, at: moment, tweak: light))
        let defocused = stats(try render(entrance: .fade, exit: .blur, at: moment, tweak: light))
        XCTAssertGreaterThan(faded.peak, 0)
        XCTAssertLessThan(defocused.peak, faded.peak, "same fade, but the glyphs are also defocused")
        XCTAssertGreaterThanOrEqual(defocused.extent, faded.extent)
    }

    func testNoneEntranceShowsTheFirstFrameImmediately() throws {
        let none = stats(try render(entrance: .none, at: 1.0))
        let fade = stats(try render(entrance: .fade, at: 1.0))
        XCTAssertGreaterThan(none.total, 1000)
        XCTAssertEqual(fade.total, 0, "the default fades in from nothing")
    }
}
