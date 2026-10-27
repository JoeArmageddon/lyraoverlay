import XCTest
import CoreGraphics
@testable import LyraCore
@testable import LyraRender

final class CinematicRenderTests: XCTestCase {
    private let viewport = CGSize(width: 640, height: 360)
    private let lyrics = """
    [00:02.00]Salt on the wind
    [00:06.00]Run
    [00:10.00]We were bright as the hours before the storm broke open
    [00:14.00]Hold on
    [00:18.00]Gold dust on the water, ash on the sky, a long road home by morning
    """

    private func renderer() throws -> MetalRenderer { try metalRendererOrSkip() }

    /// A config with no glow or shadow, so any ink is glyphs and the frame edges mean something.
    private var plain: OverlayConfig {
        var c = OverlayConfig()
        c.glow = 0
        c.shadow = 0
        c.font = FontSpec(size: 28, weight: 0.4)
        return c
    }

    private func image(at position: Double, style: LyricStyle = CinematicStyle(), config: OverlayConfig? = nil, renderer: MetalRenderer) throws -> CGImage {
        let doc = try XCTUnwrap(LRCParser.parse(lyrics))
        let frame = LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: position), position: position)
        let items = LyricsPipeline.items(style: style, frame: frame, viewport: viewport, config: config ?? plain, measurer: CoreTextMeasurer())
        return try XCTUnwrap(renderer.renderOffscreen(items, size: viewport, scale: 1))
    }

    /// RGBA bytes of a 1x render.
    private func alphaMap(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data.enumerated().filter { $0.offset % 4 == 3 }.map(\.element)
    }

    private func ink(_ alpha: [UInt8], width: Int, x: Range<Int>, y: Range<Int>) -> Int {
        var sum = 0
        for row in y { for col in x { sum += Int(alpha[row * width + col]) } }
        return sum
    }

    func testEveryShotDrawsInkInsideTheFrame() throws {
        let r = try renderer()
        // Well into each line, after its transition has finished.
        for position in [3.0, 7.0, 11.5, 15.0, 19.5] {
            let img = try image(at: position, renderer: r)
            let a = alphaMap(img)
            let total = ink(a, width: img.width, x: 0..<img.width, y: 0..<img.height)
            XCTAssertGreaterThan(total, 5_000, "a shot should draw real text at \(position)s")
        }
    }

    func testNothingTouchesTheFrameEdgeOnceTheShotHasSettled() throws {
        let r = try renderer()
        for position in [3.0, 7.0, 11.5, 15.0, 19.5] {
            let img = try image(at: position, renderer: r)
            let a = alphaMap(img), w = img.width, h = img.height
            let edge = 2
            let top = ink(a, width: w, x: 0..<w, y: 0..<edge)
            let bottom = ink(a, width: w, x: 0..<w, y: (h - edge)..<h)
            let left = ink(a, width: w, x: 0..<edge, y: 0..<h)
            let right = ink(a, width: w, x: (w - edge)..<w, y: 0..<h)
            XCTAssertEqual(top + bottom + left + right, 0, "text is clipped by the frame at \(position)s")
        }
    }

    func testTransitionFramesDifferFromTheSettledShot() throws {
        let r = try renderer()
        let forced = CinematicStyle(forcing: .hero, camera: .drift, transition: .whip)
        let early = alphaMap(try image(at: 6.03, style: forced, renderer: r))
        let settled = alphaMap(try image(at: 6.6, style: forced, renderer: r))
        XCTAssertNotEqual(early, settled)
        XCTAssertLessThan(early.reduce(0) { $0 + Int($1) }, settled.reduce(0) { $0 + Int($1) }, "an arriving shot is fainter than a landed one")
    }

    func testBlurSoftensTheArrivingShot() throws {
        let r = try renderer()
        let forced = CinematicStyle(forcing: .hero, camera: .drift, transition: .zoomThrough)
        let early = alphaMap(try image(at: 6.12, style: forced, renderer: r))
        let settled = alphaMap(try image(at: 6.8, style: forced, renderer: r))
        // Blur spreads the same ink over more pixels: a lower peak and more partly covered pixels.
        XCTAssertLessThan(early.max() ?? 0, settled.max() ?? 0)
        XCTAssertGreaterThan(early.filter { $0 > 0 }.count, 0)
    }

    func testHeroWordFillsMostOfTheWidth() throws {
        let r = try renderer()
        let forced = CinematicStyle(forcing: .hero, camera: .drift, transition: .cut)
        let img = try image(at: 7.0, style: forced, renderer: r)   // "Run"
        let a = alphaMap(img), w = img.width
        let columns = (0..<w).filter { col in (0..<img.height).contains { a[$0 * w + col] > 40 } }
        let span = (columns.last ?? 0) - (columns.first ?? 0)
        XCTAssertGreaterThan(Double(span), 0.25 * Double(w), "the hero word is big on screen")
    }

    func testWallFillsTheFrameAndOtherTemplatesRender() throws {
        let r = try renderer()
        for template in ShotTemplate.allCases {
            let img = try image(at: 12.0, style: CinematicStyle(forcing: template, transition: .cut), renderer: r)
            let a = alphaMap(img)
            XCTAssertGreaterThan(ink(a, width: img.width, x: 0..<img.width, y: 0..<img.height), 2_000, "\(template)")
        }
    }
}
