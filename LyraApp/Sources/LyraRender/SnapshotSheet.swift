import AppKit
import LyraCore

/// Renders sample frames through the real layout and Metal path and stacks them in one
/// image, so the output can be checked without a screen or any capture permission.
public enum SnapshotSheet {
    private static let sample = """
    [00:00.00]Walking down an empty street tonight
    [00:08.00]City lights are fading into the morning
    [00:16.00]Every window holds a story I could tell you if you stayed here a little longer than the rest of the quiet crowd
    """

    public static func render(renderer: MetalRenderer, config: OverlayConfig = OverlayConfig()) -> CGImage? {
        guard let doc = LRCParser.parse(sample, source: "sample") else { return nil }
        let cursor = LyricsCursor(document: doc)
        let measurer = CoreTextMeasurer()
        let style = KaraokeLineStyle()

        var config = config
        config.anchorY = 0.62   // room below for the preview line

        struct Row { var position: TimeInterval; var background: (CGFloat, CGFloat, CGFloat); var height: CGFloat }
        let rows = [
            Row(position: 1.0, background: (0.10, 0.11, 0.16), height: 200),    // early in the first line
            Row(position: 2.9, background: (0.10, 0.11, 0.16), height: 200),    // mid line
            Row(position: 2.9, background: (0.92, 0.92, 0.90), height: 200),    // same, on a light background
            Row(position: 18.5, background: (0.10, 0.11, 0.16), height: 320),   // long line that must wrap
        ]
        let width: CGFloat = 1200
        let scale: CGFloat = 2

        var images: [(CGImage, Row)] = []
        for row in rows {
            let viewport = CGSize(width: width, height: row.height)
            let frame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: row.position), position: row.position)
            let items = style.layout(frame, viewport: viewport, config: config, measurer: measurer)
            guard let image = renderer.renderOffscreen(items, size: viewport, scale: scale) else { return nil }
            images.append((image, row))
        }

        let totalHeight = rows.reduce(0) { $0 + $1.height }
        guard let ctx = CGContext(
            data: nil, width: Int(width * scale), height: Int(totalHeight * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        var top = totalHeight
        for (image, row) in images {
            let rect = CGRect(x: 0, y: top - row.height, width: width, height: row.height)
            ctx.setFillColor(CGColor(red: row.background.0, green: row.background.1, blue: row.background.2, alpha: 1))
            ctx.fill(rect)
            ctx.draw(image, in: rect)
            top -= row.height
        }
        return ctx.makeImage()
    }

    /// Edge lighting at rest, on a beat, and with a different palette, with a lyric line on top.
    public static func renderLights(renderer: MetalRenderer) -> CGImage? {
        guard let doc = LRCParser.parse(sample, source: "sample") else { return nil }
        let cursor = LyricsCursor(document: doc)
        let measurer = CoreTextMeasurer()
        let effect = RimGlowEffect()
        let style = KaraokeLineStyle()

        struct Panel { var features: AudioFeatures?; var primary: RGBA; var secondary: RGBA }
        func f(beat: Float, bass: Float, level: Float) -> AudioFeatures {
            AudioFeatures(level: level, bass: bass, mid: 0.3, treble: 0.2, beat: beat, bpm: 120, brightness: 0.4, energy: 0.5)
        }
        let panels = [
            Panel(features: f(beat: 0, bass: 0.2, level: 0.3), primary: RimGlowEffect.defaultPrimary, secondary: RimGlowEffect.defaultSecondary),
            Panel(features: f(beat: 1, bass: 0.9, level: 0.8), primary: RimGlowEffect.defaultPrimary, secondary: RimGlowEffect.defaultSecondary),
            Panel(features: f(beat: 1, bass: 0.9, level: 0.8), primary: RGBA(1, 0.45, 0.15), secondary: RGBA(1, 0.85, 0.2)),
        ]

        let size = CGSize(width: 640, height: 400)
        let scale: CGFloat = 1.5
        var config = OverlayConfig()
        config.anchorY = 0.5
        config.font = FontSpec(size: 34, weight: 0.4)

        var images: [CGImage] = []
        for (n, panel) in panels.enumerated() {
            let position = 2.9
            let frame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: position), position: position)
            let items = style.layout(frame, viewport: size, config: config, measurer: measurer)
            let params = effect.params(LightInput(features: panel.features, primary: panel.primary, secondary: panel.secondary, time: Double(n) * 3),
                                       config: LightConfig())
            guard let image = renderer.renderOffscreen(items, lights: params, size: size, scale: scale) else { return nil }
            images.append(image)
        }

        let gap: CGFloat = 12
        let totalWidth = size.width * CGFloat(images.count) + gap * CGFloat(images.count - 1)
        guard let ctx = CGContext(
            data: nil, width: Int(totalWidth * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: totalWidth, height: size.height))
        for (n, image) in images.enumerated() {
            let rect = CGRect(x: CGFloat(n) * (size.width + gap), y: 0, width: size.width, height: size.height)
            ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))
            ctx.fill(rect)
            ctx.draw(image, in: rect)
        }
        return ctx.makeImage()
    }

    public static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
