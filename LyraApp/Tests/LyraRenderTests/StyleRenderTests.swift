import XCTest
import LyraCore
@testable import LyraRender

final class StyleRenderTests: XCTestCase {
    private let size = CGSize(width: 1000, height: 300)

    private func renderer() throws -> MetalRenderer {
        try metalRendererOrSkip()
    }

    private func alphaSum(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 3, to: data.count, by: 4) { sum += Double(data[i]) }
        return sum
    }

    private func items(_ id: String, at position: TimeInterval) throws -> [DrawItem] {
        let doc = try XCTUnwrap(LRCParser.parse("[00:01.00]Walking down an empty street tonight\n[00:09.00]City lights are fading\n[00:17.00]Every window holds a story"))
        var config = OverlayConfig()
        config.anchorY = 0.5
        config.font = FontSpec(size: 40, weight: 0.4)
        let frame = LyricsFrame(lines: doc.lines, cursor: LyricsCursor(document: doc).state(at: position), position: position)
        return LyricStyles.style(id: id).layout(frame, viewport: size, config: config, measurer: CoreTextMeasurer())
    }

    func testEveryStyleRendersVisibleInkMidLine() throws {
        let r = try renderer()
        for info in LyricStyles.all {
            let drawn = try items(info.id, at: 10.5)
            XCTAssertFalse(drawn.isEmpty, info.id)
            let image = try XCTUnwrap(r.renderOffscreen(drawn, size: size, scale: 1), info.id)
            XCTAssertGreaterThan(alphaSum(image), 3000, "\(info.id) should draw visible text")
        }
    }

    func testStylesProduceDifferentImages() throws {
        let r = try renderer()
        var sums: [String: Double] = [:]
        for info in LyricStyles.all {
            let image = try XCTUnwrap(r.renderOffscreen(try items(info.id, at: 10.5), size: size, scale: 1))
            sums[info.id] = alphaSum(image)
        }
        XCTAssertEqual(Set(sums.values).count, sums.count, "no two styles should render identically: \(sums)")
    }

    func testDrawItemScaleEnlargesTheRenderedText() throws {
        let r = try renderer()
        func item(scale: Float) -> DrawItem {
            DrawItem(text: "MMMM", font: FontSpec(size: 40, weight: 0.4), center: CGPoint(x: 500, y: 150), size: CGSize(width: 120, height: 50),
                     baseColor: .white, highlightColor: .white, glowColor: .white, glow: 0, progress: 1, opacity: 1, shadow: 0, scale: scale)
        }
        let normal = try XCTUnwrap(r.renderOffscreen([item(scale: 1)], size: size, scale: 1))
        let big = try XCTUnwrap(r.renderOffscreen([item(scale: 2)], size: size, scale: 1))
        let small = try XCTUnwrap(r.renderOffscreen([item(scale: 0.5)], size: size, scale: 1))
        XCTAssertGreaterThan(alphaSum(big), alphaSum(normal) * 2.5, "twice the size is about four times the area")
        XCTAssertLessThan(alphaSum(small), alphaSum(normal) * 0.5)
    }

    func testScaledTextStaysCenteredOnItsPoint() throws {
        let r = try renderer()
        let item = DrawItem(text: "MMMM", font: FontSpec(size: 40, weight: 0.4), center: CGPoint(x: 500, y: 150), size: CGSize(width: 120, height: 50),
                            baseColor: .white, highlightColor: .white, glowColor: .white, glow: 0, progress: 1, opacity: 1, shadow: 0, scale: 1.8)
        let image = try XCTUnwrap(r.renderOffscreen([item], size: size, scale: 1))
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var minX = image.width, maxX = 0
        for y in 0..<image.height { for x in 0..<image.width where data[(y * image.width + x) * 4 + 3] > 40 { minX = min(minX, x); maxX = max(maxX, x) } }
        XCTAssertEqual(Double(minX + maxX) / 2, 500, accuracy: 6, "scaling is about the item's center, not its corner")
    }

    func testStyleSheetRenders() throws {
        let image = try XCTUnwrap(StyleSheet.render(renderer: try renderer()))
        XCTAssertGreaterThan(image.height, image.width / 2)
    }
}
