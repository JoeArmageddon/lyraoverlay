import AppKit
import CoreText
import LyraCore

/// Every lyric style rendered through the real layout and Metal path, one per row, so the
/// styles can be compared at a glance without a screen or any capture permission.
public enum StyleSheet {
    private static let sample = """
    [00:00.00]Walking down an empty street tonight
    [00:08.00]City lights are fading into the morning
    [00:16.00]Every window holds a story to tell
    """

    public static func render(renderer: MetalRenderer) -> CGImage? {
        guard let doc = LRCParser.parse(sample, source: "sample") else { return nil }
        let cursor = LyricsCursor(document: doc)
        let measurer = CoreTextMeasurer()

        var config = OverlayConfig()
        config.anchorY = 0.5
        config.font = FontSpec(size: 38, weight: 0.45)

        let size = CGSize(width: 1000, height: 280)
        let scale: CGFloat = 1.5
        let styles = LyricStyles.all

        var rows: [CGImage] = []
        for info in styles {
            // Mid-way through the second line; Pop is sampled just after a word starts so the swell shows.
            var position = 9.4
            if info.id == "pop", doc.lines[1].words.count > 2 { position = doc.lines[1].words[2].start + 0.05 }
            let frame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: position), position: position)
            let items = LyricStyles.style(id: info.id).layout(frame, viewport: size, config: config, measurer: measurer)
            guard let image = renderer.renderOffscreen(items, size: size, scale: scale) else { return nil }
            rows.append(image)
        }

        let total = CGSize(width: size.width, height: size.height * CGFloat(rows.count))
        guard let ctx = CGContext(
            data: nil, width: Int(total.width * scale), height: Int(total.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)

        var top = total.height
        for (n, image) in rows.enumerated() {
            let rect = CGRect(x: 0, y: top - size.height, width: size.width, height: size.height)
            ctx.setFillColor(CGColor(red: 0.08 + 0.01 * CGFloat(n % 2), green: 0.09, blue: 0.12, alpha: 1))
            ctx.fill(rect)
            ctx.draw(image, in: rect)
            drawLabel(styles[n].name, in: ctx, at: CGPoint(x: 14, y: rect.maxY - 24))
            top -= size.height
        }
        return ctx.makeImage()
    }

    private static func drawLabel(_ text: String, in ctx: CGContext, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(white: 0.55, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text.uppercased(), attributes: attrs))
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }
}
