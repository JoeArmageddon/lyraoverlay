import Foundation
import CoreGraphics

/// Words appear only as they are sung; the previous line fades out above. Words that have
/// not started are not drawn at all (not just transparent), so they leave no halo behind.
public struct TypewriterStyle: LyricStyle {
    public let name = "Typewriter"

    /// How long the previous line takes to fade after the current one starts.
    private let previousFade = 1.2

    public init() {}

    public func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem] {
        guard !frame.lines.isEmpty, let index = frame.cursor.lineIndex else { return [] }
        let line = frame.lines[index]
        let maxWidth = viewport.width * config.maxWidthFraction
        let centerY = viewport.height * (1 - config.anchorY)
        var items: [DrawItem] = []
        var blockTop = centerY

        if !line.isInstrumentalGap, !line.words.isEmpty {
            let opacity = StyleKit.lineOpacity(line, position: frame.position, config: config)
            if opacity > 0 {
                // Positions come from the whole line so revealed words never shift as more appear.
                let block = StyleKit.block(words: line.words.map(\.text), font: config.font, viewport: viewport,
                                           centerY: centerY, maxWidth: maxWidth, lineSpacing: config.lineSpacing, measurer: measurer)
                let hidden = config.baseColor.withAlpha(0)
                for p in block.words {
                    let progress = StyleKit.wordProgress(p.index, frame.cursor)
                    guard progress > 0 else { continue }
                    items.append(DrawItem(
                        text: p.text, font: config.font, center: p.center,
                        size: CGSize(width: p.width, height: block.rowHeight),
                        baseColor: hidden, highlightColor: config.highlightColor,
                        glowColor: config.glowColor, glow: config.glow,
                        // The halo is drawn from the glyph shapes, not the wipe, so a half-typed word would show a
                        // dark smudge where its unsung part is invisible. Only finished words get one.
                        progress: progress, opacity: opacity, shadow: progress >= 1 ? config.shadow : 0,
                        lineIndex: index, wordIndex: p.index))
                }
                blockTop = block.top
            }
        }

        if index > 0 {
            let previous = frame.lines[index - 1]
            let fade = 1 - StyleKit.smooth((frame.position - line.start) / previousFade)
            if !previous.isInstrumentalGap, fade > 0 {
                let small = config.font.withSize(config.font.size * config.secondaryScale)
                let dim = config.highlightColor.scaledAlpha(config.secondaryOpacity)
                items.append(StyleKit.singleLine(
                    previous.text, font: small,
                    center: CGPoint(x: viewport.width / 2, y: blockTop - measurer.lineHeight(font: small) * 0.9),
                    maxWidth: maxWidth, measurer: measurer, base: dim, highlight: dim, progress: 1,
                    opacity: Float(fade), config: config, lineIndex: index - 1))
            }
        }
        return items
    }
}
