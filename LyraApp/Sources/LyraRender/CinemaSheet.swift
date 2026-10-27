import AppKit
import LyraCore

/// Renders the film-look effects through the real layout and Metal path, one 16:9 panel per
/// stage, so they can be judged without a window or screen-capture permission.
public enum CinemaSheet {
    public static func render(renderer: MetalRenderer) -> CGImage? {
        guard let doc = LRCParser.parse("[00:00.00]Neon rain on the empty avenue tonight\n[00:09.00]Next line", source: "sample") else { return nil }
        let measurer = CoreTextMeasurer()
        let position = 3.1
        let cursor = LyricsCursor(document: doc).state(at: position)

        let panelSize = CGSize(width: 560, height: 315)
        let scale: CGFloat = 1.5
        let effect = RimGlowEffect()

        // Four stages: untouched, bars, bars + vignette + grain, everything with a flare on a beat.
        struct Stage { var title: String; var cinema: CinemaSettings?; var beat: Float }
        func cinema(_ mutate: (inout CinemaSettings) -> Void) -> CinemaSettings {
            var s = CinemaSettings()
            s.enabled = true
            s.vignette = 0; s.grain = 0; s.flare = 0
            mutate(&s)
            return s
        }
        let stages = [
            Stage(title: "original", cinema: nil, beat: 0),
            Stage(title: "+ letterbox", cinema: cinema { $0.letterbox = .cinemascope }, beat: 0),
            Stage(title: "+ vignette, grain", cinema: cinema { $0.letterbox = .cinemascope; $0.vignette = 0.55; $0.grain = 0.22 }, beat: 0),
            Stage(title: "+ flare on a beat", cinema: cinema { $0.letterbox = .cinemascope; $0.vignette = 0.55; $0.grain = 0.22; $0.flare = 0.8 }, beat: 1),
        ]

        var images: [CGImage] = []
        for (n, stage) in stages.enumerated() {
            let settings = stage.cinema ?? CinemaSettings()
            let region = PlayerFrameBuilder.lyricRegion(cinema: settings, viewport: panelSize)
            let config = PlayerFrameBuilder.lyricConfig(base: OverlayConfig(), albumPalette: nil, useArtworkColors: false,
                                                        viewportWidth: region.width, lyricsScale: 1.8)
            var centered = config
            centered.anchorY = 0.5
            let frame = LyricsFrame(lines: doc.lines, cursor: cursor, position: position, beat: stage.beat, bass: 0.6)
            var items = KaraokeLineStyle().layout(frame, viewport: region.size, config: centered, measurer: measurer)

            // Mark the longest word of the CURRENT line as the hero, the way a real style would
            // (the dimmer preview of the next line is not a candidate).
            let current = items.indices.filter { items[$0].lineIndex == cursor.lineIndex }
            if let hero = current.max(by: { items[$0].text.count < items[$1].text.count }) { items[hero].isEmphasis = true }
            items = PlayerFrameBuilder.shifted(items, by: region.origin)

            let features = AudioFeatures(level: 0.6, bass: 0.6, mid: 0.3, treble: 0.2, beat: stage.beat, bpm: 120, brightness: 0.4, energy: 0.5)
            var lightConfig = LightConfig()
            lightConfig.thickness = 22
            let lights = effect.params(LightInput(features: features, primary: RGBA(0.55, 0.5, 1), secondary: RGBA(1, 0.45, 0.7), time: Double(n)),
                                       config: lightConfig)
            let cinemaFrame = stage.cinema.flatMap {
                CinemaEffect.frame(settings: $0, viewport: panelSize, beat: stage.beat, bass: 0.6,
                                   emphasisCenter: PlayerFrameBuilder.emphasisCenter(in: items), time: 41.0 + Double(n))
            }
            guard let image = renderer.renderOffscreen(items, lights: lights, cinema: cinemaFrame, size: panelSize, scale: scale) else { return nil }
            images.append(image)
        }

        let gap: CGFloat = 14
        let total = CGSize(width: panelSize.width * 4 + gap * 3, height: panelSize.height)
        guard let ctx = CGContext(
            data: nil, width: Int(total.width * scale), height: Int(total.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: total))

        for (n, image) in images.enumerated() {
            let rect = CGRect(x: CGFloat(n) * (panelSize.width + gap), y: 0, width: panelSize.width, height: panelSize.height)
            drawBackdrop(in: ctx, rect: rect)
            ctx.draw(image, in: rect)
        }
        return ctx.makeImage()
    }

    /// A colorful backdrop with a bright and a dark region, so the effects have something to act on.
    private static func drawBackdrop(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.clip(to: rect)
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [CGColor(red: 0.10, green: 0.16, blue: 0.45, alpha: 1), CGColor(red: 0.62, green: 0.18, blue: 0.55, alpha: 1),
                      CGColor(red: 0.98, green: 0.52, blue: 0.30, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        }
        // A soft warm light, like a window in the distance.
        let glow = [CGColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.55), CGColor(red: 1, green: 0.85, blue: 0.6, alpha: 0)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
            let c = CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY + rect.height * 0.3)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: rect.width * 0.28, options: [])
        }
        ctx.restoreGState()
    }
}
