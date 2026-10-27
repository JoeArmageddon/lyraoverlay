import Foundation
import CoreGraphics

/// Like Karaoke Line, but each word pops when it starts: it swells, springs back and
/// hops up a little, all derived from the time since the word began.
public struct PopStyle: LyricStyle {
    public let name = "Pop"

    private let swell = 0.18
    private let hop = 0.14

    public init() {}

    public func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem] {
        guard !frame.lines.isEmpty, let index = frame.cursor.lineIndex else { return [] }
        let line = frame.lines[index]
        guard !line.isInstrumentalGap, !line.words.isEmpty else { return [] }

        let opacity = StyleKit.lineOpacity(line, position: frame.position, config: config)
        guard opacity > 0 else { return [] }

        let block = StyleKit.block(words: line.words.map(\.text), font: config.font, viewport: viewport,
                                   centerY: viewport.height * (1 - config.anchorY),
                                   maxWidth: viewport.width * config.maxWidthFraction,
                                   lineSpacing: config.lineSpacing, measurer: measurer)
        return block.words.map { p in
            let age = frame.position - line.words[p.index].start
            let e = StyleKit.popEnvelope(age)
            // The cosine makes it overshoot, dip below rest size, and settle.
            let scale = 1 + swell * e * cos(14 * max(0, age))
            let lift = -hop * config.font.size * e
            return DrawItem(
                text: p.text, font: config.font,
                center: CGPoint(x: p.center.x, y: p.center.y + lift),
                size: CGSize(width: p.width, height: block.rowHeight),
                baseColor: config.baseColor, highlightColor: config.highlightColor,
                glowColor: config.glowColor, glow: config.glow,
                progress: StyleKit.wordProgress(p.index, frame.cursor),
                opacity: opacity, shadow: config.shadow, scale: Float(scale),
                lineIndex: index, wordIndex: p.index)
        }
    }
}
