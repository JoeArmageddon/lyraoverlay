import AppKit
import LyraCore

/// Renders corner mode onto stand-in desktops, one corner per panel, through the real layout and Metal
/// path, so the look can be checked without music playing or a window on the user's screen.
public enum CornerSheet {
    private static let sample = """
    [00:00.00]Walking down an empty street tonight
    [00:09.00]City lights are fading into the morning
    [00:18.00]Every window holds a story to tell
    """

    public static func render(renderer: MetalRenderer) -> CGImage? {
        guard let doc = LRCParser.parse(sample, source: "sample") else { return nil }
        let cursor = LyricsCursor(document: doc)
        let measurer = CoreTextMeasurer()
        let style = KaraokeLineStyle()

        // A 1512x982 screen with a 33 pt menu bar on top and a 70 pt Dock below.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)

        struct Panel { var corner: ScreenCorner; var nextLine: Bool; var bright: Bool; var position: TimeInterval }
        let panels = [
            Panel(corner: .bottomRight, nextLine: false, bright: false, position: 3.0),
            Panel(corner: .topRight, nextLine: true, bright: true, position: 12.5),
            Panel(corner: .bottomLeft, nextLine: false, bright: true, position: 5.0),
            Panel(corner: .topLeft, nextLine: true, bright: false, position: 21.0),
        ]

        let scale: CGFloat = 2
        let panelSize = CGSize(width: screen.width / 2, height: screen.height / 2)   // each panel shows the screen at 50%
        guard let ctx = CGContext(
            data: nil, width: Int(screen.width * scale), height: Int(screen.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high

        for (n, panel) in panels.enumerated() {
            var settings = CornerOverlaySettings()
            settings.enabled = true
            settings.corner = panel.corner
            settings.showNextLine = panel.nextLine

            let frame = CornerOverlay.frame(in: visible, settings: settings)
            let cardSize = frame.size
            let config = CornerOverlay.config(from: OverlayConfig(), settings: settings)
            let lyricsFrame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: panel.position), position: panel.position)
            let items = style.layout(lyricsFrame, viewport: cardSize, config: config, measurer: measurer)
            guard let card = renderer.renderOffscreen(items, panel: CornerOverlay.backdrop(for: settings, size: cardSize),
                                                      size: cardSize, scale: scale) else { return nil }

            // Draw this panel's mini-desktop into its quadrant (column n % 2, row n / 2 from the top).
            let origin = CGPoint(x: CGFloat(n % 2) * panelSize.width, y: screen.height - CGFloat(n / 2 + 1) * panelSize.height)
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: 0.5, y: 0.5)
            ctx.clip(to: screen)
            drawDesktop(ctx, screen: screen, visible: visible, bright: panel.bright)
            ctx.draw(card, in: frame)   // the card image is already `scale` times larger; the context handles it
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    /// A stand-in desktop: wallpaper gradient, a menu bar, a Dock and one big app window. The bright
    /// version has a white document window so low-contrast text would show up.
    private static func drawDesktop(_ ctx: CGContext, screen: CGRect, visible: CGRect, bright: Bool) {
        let colors: [CGColor] = bright
            ? [CGColor(red: 0.93, green: 0.94, blue: 0.97, alpha: 1), CGColor(red: 0.80, green: 0.86, blue: 0.95, alpha: 1)]
            : [CGColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1), CGColor(red: 0.30, green: 0.16, blue: 0.38, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: screen.maxY), end: CGPoint(x: screen.maxX, y: 0), options: [])
        }
        // An app window with a title bar and some "text" lines.
        let window = CGRect(x: 180, y: 130, width: 1150, height: 700)
        ctx.setFillColor(bright ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0.16, alpha: 1))
        ctx.fill(window)
        ctx.setFillColor(bright ? CGColor(gray: 0.90, alpha: 1) : CGColor(gray: 0.22, alpha: 1))
        ctx.fill(CGRect(x: window.minX, y: window.maxY - 40, width: window.width, height: 40))
        ctx.setFillColor(bright ? CGColor(gray: 0.35, alpha: 0.55) : CGColor(gray: 0.8, alpha: 0.35))
        for row in 0..<14 {
            let y = window.maxY - 90 - CGFloat(row) * 40
            ctx.fill(CGRect(x: window.minX + 40, y: y, width: CGFloat(300 + (row * 97) % 650), height: 14))
        }
        // Menu bar and Dock.
        ctx.setFillColor(CGColor(gray: bright ? 0.97 : 0.05, alpha: 0.85))
        ctx.fill(CGRect(x: 0, y: screen.maxY - 33, width: screen.width, height: 33))
        ctx.setFillColor(CGColor(gray: bright ? 1 : 0.2, alpha: 0.55))
        ctx.fill(CGRect(x: screen.midX - 260, y: 8, width: 520, height: 56))
    }
}
