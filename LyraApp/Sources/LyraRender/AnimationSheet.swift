import AppKit
import CoreText
import LyraCore

/// Every entrance animation, one per row, frozen partway through (35% of its duration) so the
/// differences are visible in a still image. Goes through the real pipeline and Metal path.
public enum AnimationSheet {
    private static let sample = "[00:00.00]Morning light on the quiet water"

    public static func render(renderer: MetalRenderer) -> CGImage? {
        guard let doc = LRCParser.parse(sample, source: "sample") else { return nil }
        let cursor = LyricsCursor(document: doc)
        let measurer = CoreTextMeasurer()
        let style = KaraokeLineStyle()

        let duration = 1.0

        var config = OverlayConfig()
        config.anchorY = 0.5
        config.showNextLine = false
        config.font = FontSpec(size: 40, weight: 0.45)
        config.entranceDuration = duration
        config.entranceStagger = 0.05
        // A very short baked fade-in, so what the rows show is the animation, not the fade underneath.
        config.fadeInDuration = 0.05

        /// Where in its entrance each kind is frozen. Glitch is a burst over the first third, so
        /// 35% would catch it just as it settles and it would look like no animation at all.
        func progress(_ kind: EntranceAnimation) -> Double { kind == .glitch ? 0.12 : 0.35 }

        let size = CGSize(width: 1000, height: 150)
        let scale: CGFloat = 1.5
        let kinds = EntranceAnimation.allCases

        var rows: [CGImage] = []
        for kind in kinds {
            config.entrance = kind
            let position = duration * progress(kind)
            let frame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: position), position: position)
            let items = LyricsPipeline.items(style: style, frame: frame, viewport: size, config: config, measurer: measurer)
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
            ctx.setFillColor(CGColor(red: 0.08 + 0.012 * CGFloat(n % 2), green: 0.09, blue: 0.12, alpha: 1))
            ctx.fill(rect)
            // A faint guide at the line's resting position, so the offset of each kind reads clearly.
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: 0, y: rect.midY - 30, width: size.width, height: 60))
            ctx.draw(image, in: rect)
            drawLabel("\(kinds[n].title) at \(Int(progress(kinds[n]) * 100))%", in: ctx, at: CGPoint(x: 14, y: rect.maxY - 22))
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
