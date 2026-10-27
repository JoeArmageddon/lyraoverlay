import XCTest
import LyraCore
@testable import LyraRender

final class RenderTests: XCTestCase {
    private func renderer() throws -> MetalRenderer {
        try metalRendererOrSkip()
    }

    private func item(_ text: String = "MMMMMMMM", progress: Float, glow: Float = 0, shadow: Float = 0) -> DrawItem {
        DrawItem(text: text, font: FontSpec(size: 64, weight: 0.4), center: CGPoint(x: 300, y: 100), size: CGSize(width: 400, height: 80),
                 baseColor: RGBA(1, 1, 1, 0.25), highlightColor: RGBA(1, 1, 1, 1), glowColor: RGBA(0, 0.5, 1, 1),
                 glow: glow, progress: progress, opacity: 1, shadow: shadow)
    }

    /// Sum of premultiplied color+alpha over a pixel column range.
    private func ink(_ image: CGImage, columns: Range<Int>, rows: Range<Int>? = nil) -> Double {
        let w = image.width, h = image.height
        let rows = rows ?? 0..<h
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for y in rows { for x in columns { sum += Double(data[(y * w + x) * 4 + 3]) } }
        return sum
    }

    func testNothingDrawnIsFullyTransparent() throws {
        let image = try XCTUnwrap(renderer().renderOffscreen([], size: CGSize(width: 200, height: 100), scale: 1))
        XCTAssertEqual(ink(image, columns: 0..<image.width), 0)
    }

    func testTextProducesPixelsAndCachesItsTexture() throws {
        let r = try renderer()
        let image = try XCTUnwrap(r.renderOffscreen([item(progress: 1)], size: CGSize(width: 600, height: 200), scale: 1))
        XCTAssertGreaterThan(ink(image, columns: 0..<image.width), 1000)
        let cached = r.textures.count
        _ = r.renderOffscreen([item(progress: 1)], size: CGSize(width: 600, height: 200), scale: 1)
        XCTAssertEqual(r.textures.count, cached, "same text and font must reuse its texture")
    }

    func testSungPartIsBrighterThanTheRest() throws {
        let r = try renderer()
        let image = try XCTUnwrap(r.renderOffscreen([item(progress: 0.5)], size: CGSize(width: 600, height: 200), scale: 1))
        // Text spans roughly the middle of the view; compare its left and right halves.
        let sung = ink(image, columns: 150..<300)
        let unsung = ink(image, columns: 300..<450)
        XCTAssertGreaterThan(sung, unsung * 2, "highlight is alpha 1.0, base is 0.25")
    }

    func testProgressZeroAndOneDiffer() throws {
        let r = try renderer()
        let none = try XCTUnwrap(r.renderOffscreen([item(progress: 0)], size: CGSize(width: 600, height: 200), scale: 1))
        let all = try XCTUnwrap(r.renderOffscreen([item(progress: 1)], size: CGSize(width: 600, height: 200), scale: 1))
        XCTAssertGreaterThan(ink(all, columns: 0..<600), ink(none, columns: 0..<600) * 2)
    }

    func testGlowAddsInkOutsideTheGlyphs() throws {
        let r = try renderer()
        let plain = try XCTUnwrap(r.renderOffscreen([item(progress: 1)], size: CGSize(width: 600, height: 200), scale: 1))
        let glowing = try XCTUnwrap(r.renderOffscreen([item(progress: 1, glow: 1)], size: CGSize(width: 600, height: 200), scale: 1))
        XCTAssertGreaterThan(ink(glowing, columns: 0..<600), ink(plain, columns: 0..<600))
    }

    func testOpacityZeroDrawsNothing() throws {
        var hidden = item(progress: 1)
        hidden.opacity = 0
        let image = try XCTUnwrap(renderer().renderOffscreen([hidden], size: CGSize(width: 600, height: 200), scale: 1))
        XCTAssertEqual(ink(image, columns: 0..<image.width), 0)
    }

    // MARK: - Edge lighting

    private func lights(intensity: Float = 1, thickness: Double = 24, radius: Double = 14) -> LightParams {
        LightParams(primary: RGBA(0.2, 0.5, 1), secondary: RGBA(1, 0.3, 0.8), thickness: thickness,
                    cornerRadius: radius, intensity: intensity, phase: 0)
    }

    /// Alpha (0...255) at a pixel of a 1x render.
    private func alpha(_ image: CGImage, x: Int, y: Int) -> Int {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Int(data[(y * w + x) * 4 + 3])
    }

    func testGlowIsBrightAtTheEdgeAndGoneInTheMiddle() throws {
        let size = CGSize(width: 800, height: 500)
        let image = try XCTUnwrap(renderer().renderOffscreen([], lights: lights(), size: size, scale: 1))
        XCTAssertGreaterThan(alpha(image, x: 400, y: 1), 150, "top edge")
        XCTAssertGreaterThan(alpha(image, x: 1, y: 250), 150, "left edge")
        XCTAssertGreaterThan(alpha(image, x: 798, y: 250), 150, "right edge")
        XCTAssertGreaterThan(alpha(image, x: 400, y: 498), 150, "bottom edge")
        XCTAssertEqual(alpha(image, x: 400, y: 250), 0, "center is untouched")
        XCTAssertLessThan(alpha(image, x: 400, y: 100), alpha(image, x: 400, y: 10), "fades inward")
    }

    func testStripsJoinWithoutSeamsOrDoubleBrightness() throws {
        // On a straight edge the glow must not change along it. Strips that overlapped, or
        // a gap between them, would show as a jump near the strip boundary (about 5 falloffs in).
        let size = CGSize(width: 800, height: 500)
        let image = try XCTUnwrap(renderer().renderOffscreen([], lights: lights(thickness: 24), size: size, scale: 1))
        let column = (60..<440).map { alpha(image, x: 3, y: $0) }
        XCTAssertLessThanOrEqual(column.max()! - column.min()!, 6, "left edge should be uniform along its length")
        let row = (60..<740).map { alpha(image, x: $0, y: 3) }
        // The gradient rotates around the screen, which changes color but never alpha.
        XCTAssertLessThanOrEqual(row.max()! - row.min()!, 6, "top edge should be uniform along its length")
    }

    func testGlowFollowsTheRoundedCorner() throws {
        let r = try renderer()
        let size = CGSize(width: 600, height: 400)
        let round = try XCTUnwrap(r.renderOffscreen([], lights: lights(thickness: 12, radius: 40), size: size, scale: 1))
        let square = try XCTUnwrap(r.renderOffscreen([], lights: lights(thickness: 12, radius: 0), size: size, scale: 1))
        // The 45-degree point of a radius-40 corner is about 12 px in from both sides, right on
        // the curve, where the glow is brightest. With a square corner that pixel is 12 px from the edge.
        XCTAssertGreaterThan(alpha(round, x: 12, y: 12), alpha(square, x: 12, y: 12) + 40)
    }

    func testIntensityScalesTheGlowAndZeroDrawsNothing() throws {
        let r = try renderer()
        let size = CGSize(width: 600, height: 400)
        let bright = try XCTUnwrap(r.renderOffscreen([], lights: lights(intensity: 1), size: size, scale: 1))
        let dim = try XCTUnwrap(r.renderOffscreen([], lights: lights(intensity: 0.3), size: size, scale: 1))
        let off = try XCTUnwrap(r.renderOffscreen([], lights: lights(intensity: 0), size: size, scale: 1))
        XCTAssertGreaterThan(alpha(bright, x: 300, y: 2), alpha(dim, x: 300, y: 2) * 2)
        XCTAssertEqual(ink(off, columns: 0..<off.width), 0)
    }

    func testThickerGlowReachesFurtherIn() throws {
        let r = try renderer()
        let size = CGSize(width: 800, height: 500)
        let thin = try XCTUnwrap(r.renderOffscreen([], lights: lights(thickness: 10), size: size, scale: 1))
        let thick = try XCTUnwrap(r.renderOffscreen([], lights: lights(thickness: 50), size: size, scale: 1))
        XCTAssertGreaterThan(alpha(thick, x: 400, y: 60), alpha(thin, x: 400, y: 60) + 20)
    }

    func testLyricsDrawOverTheLights() throws {
        let r = try renderer()
        let size = CGSize(width: 800, height: 500)
        let text = DrawItem(text: "MMMM", font: FontSpec(size: 90, weight: 0.5), center: CGPoint(x: 400, y: 250), size: CGSize(width: 300, height: 100),
                            baseColor: .white, highlightColor: .white, glowColor: .white, glow: 0, progress: 1, opacity: 1)
        let with = try XCTUnwrap(r.renderOffscreen([text], lights: lights(), size: size, scale: 1))
        let without = try XCTUnwrap(r.renderOffscreen([text], size: size, scale: 1))
        // The middle of the screen has no glow, so any ink there is the text, and adding the lights must not change it.
        let middle = 150..<350
        XCTAssertGreaterThan(ink(with, columns: 250..<550, rows: middle), 5000)
        XCTAssertEqual(ink(with, columns: 250..<550, rows: middle), ink(without, columns: 250..<550, rows: middle), accuracy: 1)
        XCTAssertGreaterThan(alpha(with, x: 400, y: 1), 150, "lights still draw at the edge")
    }

    func testRimUniformsMatchTheShaderLayout() {
        // 72 bytes of fields in a 16-byte aligned struct.
        XCTAssertEqual(MemoryLayout<MetalRenderer.RimUniforms>.stride, 80)
    }

    func testMeasurerGrowsWithTextAndSize() {
        let m = CoreTextMeasurer()
        let f = FontSpec(size: 40)
        XCTAssertGreaterThan(m.width(of: "hello world", font: f), m.width(of: "hello", font: f))
        XCTAssertGreaterThan(m.width(of: "hello", font: f.withSize(80)), m.width(of: "hello", font: f))
        XCTAssertGreaterThan(m.lineHeight(font: f), 40)
    }

    func testUnknownFontFallsBackInsteadOfFailing() {
        let m = CoreTextMeasurer()
        XCTAssertGreaterThan(m.width(of: "hello", font: FontSpec(family: "Definitely Not A Font", size: 40)), 0)
    }

    func testUniformsMatchTheShaderLayout() {
        // 16-byte aligned struct: 108 bytes of fields rounded up to 112.
        XCTAssertEqual(MemoryLayout<MetalRenderer.Uniforms>.stride, 112)
    }

    func testSettingsRoundTripAndCorruptFileFallsBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyra-settings-\(UUID().uuidString).json")
        let store = SettingsStore(url: url)
        XCTAssertEqual(store.load(), AppSettings(), "missing file gives defaults")

        var s = AppSettings()
        s.overlay.latencyOffset = 0.3
        s.level = .aboveEverything
        s.allDisplays = false
        store.save(s)
        XCTAssertEqual(store.load(), s)

        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(store.load(), AppSettings(), "corrupt file gives defaults")
    }
}
