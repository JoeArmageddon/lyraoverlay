import AppKit
import LyraCore

/// Renders the current settings over sample lyrics and a simulated beat, through the same
/// layout and Metal path as the real overlay, so the settings window shows exactly what
/// the overlay will draw.
final class PreviewRenderer {
    private let renderer: MetalRenderer
    private let measurer = CoreTextMeasurer()
    private let effect = RimGlowEffect()

    /// A made-up cover palette so "Match Album Colors" has a visible effect in the preview.
    private let samplePalette = Palette(
        dominant: RGBA(0.12, 0.1, 0.2), accent: RGBA(0.5, 0.35, 0.9), secondary: RGBA(0.95, 0.5, 0.6),
        swatches: [], isDark: true)

    /// Neutral sample text; the preview loops over it.
    private let document = LRCParser.parse("""
    [00:00.00]Walking down an empty street tonight
    [00:05.50]City lights are fading into the morning
    [00:11.00]Every window holds a story to tell
    """, source: "preview")!
    private let loopLength = 15.0

    init(renderer: MetalRenderer) { self.renderer = renderer }

    func image(settings: AppSettings, time: Double, size: CGSize, scale: CGFloat) -> NSImage? {
        let position = time.truncatingRemainder(dividingBy: loopLength) + 0.3
        let cursor = LyricsCursor(document: document)

        var config = ThemeResolver.resolve(settings.overlay, palette: samplePalette, useArtworkColors: settings.useArtworkColors)
        config.latencyOffset = 0
        // Match the overlay's text-case handling.
        let doc = document.applying(config.textCase)
        let frame = LyricsFrame(lines: doc.lines, cursor: cursor.state(at: position), position: position)
        // The overlay sits near the bottom of a tall screen; center the line in the preview instead.
        var previewConfig = config
        previewConfig.anchorY = 0.5
        let items = LyricsPipeline.items(style: LyricStyles.style(id: settings.styleID), frame: frame, viewport: size,
                                         config: previewConfig, measurer: measurer)

        // Simulate music: a 120 BPM beat with a bassy body.
        let beatPhase = time.truncatingRemainder(dividingBy: 0.5)
        let features = AudioFeatures(level: 0.5, bass: Float(0.4 + 0.5 * exp(-beatPhase / 0.15)), mid: 0.3, treble: 0.2,
                                     beat: Float(exp(-beatPhase / 0.2)), bpm: 120, brightness: 0.4, energy: 0.5)
        let colors = settings.lights.useArtworkColors
            ? (samplePalette.lightPrimary, samplePalette.lightSecondary)
            : (RimGlowEffect.defaultPrimary, RimGlowEffect.defaultSecondary)
        let lights = effect.params(LightInput(features: features, primary: colors.0, secondary: colors.1, time: time),
                                   config: settings.lights)

        guard let cg = renderer.renderOffscreen(items, lights: lights, size: size, scale: scale) else { return nil }
        return NSImage(cgImage: cg, size: size)
    }
}
