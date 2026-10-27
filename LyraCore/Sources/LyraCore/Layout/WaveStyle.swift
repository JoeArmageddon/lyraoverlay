import Foundation
import CoreGraphics

/// Words ride a travelling sine wave, and the word being sung lifts above the rest.
public struct WaveStyle: LyricStyle {
    public let name = "Wave"

    /// Crest height as a fraction of the font size.
    private let amplitude = 0.10
    /// Distance between crests, in font sizes.
    private let wavelength = 6.0
    /// Crests travelling along the line, in cycles per second.
    private let speed = 0.7
    /// How far the current word rises, as a fraction of the font size.
    private let lift = 0.2

    public init() {}

    public func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem] {
        guard !frame.lines.isEmpty, let index = frame.cursor.lineIndex else { return [] }
        let line = frame.lines[index]
        guard !line.isInstrumentalGap, !line.words.isEmpty else { return [] }

        let opacity = StyleKit.lineOpacity(line, position: frame.position, config: config)
        guard opacity > 0 else { return [] }

        let size = config.font.size
        let block = StyleKit.block(words: line.words.map(\.text), font: config.font, viewport: viewport,
                                   centerY: viewport.height * (1 - config.anchorY),
                                   maxWidth: viewport.width * config.maxWidthFraction,
                                   lineSpacing: config.lineSpacing, measurer: measurer)
        return block.words.map { p in
            // Phase follows the word's horizontal position, so the whole line looks like one wave.
            let phase = 2 * Double.pi * (Double(p.center.x) / (size * wavelength) - frame.position * speed)
            var dy = amplitude * size * sin(phase)

            if frame.cursor.isSinging, frame.cursor.wordIndex == p.index {
                // Rise and fall over the word's duration.
                dy -= lift * size * sin(Double.pi * frame.cursor.wordProgress)
            }
            return DrawItem(
                text: p.text, font: config.font,
                center: CGPoint(x: p.center.x, y: p.center.y + dy),
                size: CGSize(width: p.width, height: block.rowHeight),
                baseColor: config.baseColor, highlightColor: config.highlightColor,
                glowColor: config.glowColor, glow: config.glow,
                progress: StyleKit.wordProgress(p.index, frame.cursor),
                opacity: opacity, shadow: config.shadow,
                lineIndex: index, wordIndex: p.index)
        }
    }
}
