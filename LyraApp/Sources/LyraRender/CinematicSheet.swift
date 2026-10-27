import AppKit
import CoreText
import LyraCore

/// The Cinematic style rendered through the real layout and Metal path as a contact sheet: twelve
/// consecutive shots of invented lyrics (about 70 percent through each), plus one shot caught
/// at three moments of its transition. Checked by eye, with no screen or capture permission.
public enum CinematicSheet {
    /// Invented lines of varied length, none from a real song.
    static let sampleLines = [
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

    public static func render(renderer: MetalRenderer, config: OverlayConfig = OverlayConfig()) -> CGImage? {
        let lrc = sampleLines.enumerated().map { i, text in
            let t = 2 + i * 4
            return String(format: "[%02d:%02d.00]%@", t / 60, t % 60, text)
        }.joined(separator: "\n")
        guard let doc = LRCParser.parse(lrc, source: "sample") else { return nil }
        let cursor = LyricsCursor(document: doc)
        let measurer = CoreTextMeasurer()
        let style = CinematicStyle()

        // Every thumbnail is a 16:9 frame laid out at a typical screen size, then shrunk to fit.
        let viewport = CGSize(width: 1280, height: 720)
        let scale: CGFloat = 0.6
        let thumb = CGSize(width: viewport.width * scale, height: viewport.height * scale)

        func shot(_ position: Double) -> CGImage? {
            let frame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: position), position: position)
            let items = LyricsPipeline.items(style: style, frame: frame, viewport: viewport, config: config, measurer: measurer)
            return renderer.renderOffscreen(items, size: viewport, scale: scale)
        }

        struct Cell { var image: CGImage; var label: String }
        var cells: [Cell] = []
        for i in doc.lines.indices {
            let line = doc.lines[i]
            let position = line.start + 0.7 * (line.sungEnd - line.start)
            guard let image = shot(position), let info = CinematicStyle.describeShot(lineIndex: i, in: doc.lines) else { return nil }
            cells.append(Cell(image: image, label: "\(i + 1) · \(info.template) · \(info.transition)"))
        }

        // One shot caught at 5, 15, 40 and 100 percent of its arrival. A hero shot shows it best:
        // its big word arrives first, with no stagger to hide the motion.
        var transition: [Cell] = []
        func moves(_ i: Int) -> Bool { (CinematicStyle.describeShot(lineIndex: i, in: doc.lines)?.entranceDuration ?? 0) > 0 }
        let pick = doc.lines.indices.first { moves($0) && CinematicStyle.describeShot(lineIndex: $0, in: doc.lines)?.template == "hero" }
            ?? doc.lines.indices.first(where: moves)
        if let i = pick, let info = CinematicStyle.describeShot(lineIndex: i, in: doc.lines) {
            let start = doc.lines[i].start
            for (fraction, name) in [(0.05, "5%"), (0.15, "15%"), (0.4, "40%"), (1.0, "100%")] {
                // 100% also waits out the small per-word delays, so every word has landed.
                let position = start + info.entranceDuration * fraction + (fraction >= 1 ? 0.18 : 0)
                guard let image = shot(position) else { return nil }
                transition.append(Cell(image: image, label: "line \(i + 1) · \(info.transition) · \(name) of arrival"))
            }
        }

        let columns = 4
        let gap: CGFloat = 10
        let rows = 3 + (transition.isEmpty ? 0 : 1)
        let total = CGSize(width: CGFloat(columns) * thumb.width + gap * CGFloat(columns + 1),
                           height: CGFloat(rows) * thumb.height + gap * CGFloat(rows + 1))
        guard let ctx = CGContext(
            data: nil, width: Int(total.width), height: Int(total.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.045, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: total))

        func draw(_ cell: Cell, column: Int, row: Int) {
            let rect = CGRect(x: gap + CGFloat(column) * (thumb.width + gap),
                              y: total.height - (gap + CGFloat(row + 1) * thumb.height + CGFloat(row) * gap),
                              width: thumb.width, height: thumb.height)
            ctx.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1))
            ctx.fill(rect)
            ctx.draw(cell.image, in: rect)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
            ctx.setLineWidth(1)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            drawLabel(cell.label, in: ctx, at: CGPoint(x: rect.minX + 8, y: rect.maxY - 18))
        }
        for (n, cell) in cells.enumerated() { draw(cell, column: n % columns, row: n / columns) }
        for (n, cell) in transition.enumerated() { draw(cell, column: n, row: 3) }
        return ctx.makeImage()
    }

    private static func drawLabel(_ text: String, in ctx: CGContext, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 0.62, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }
}
