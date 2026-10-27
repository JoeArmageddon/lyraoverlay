import Foundation
import CoreGraphics

/// Several lines at once. The current line is at the anchor at full size with the word wipe;
/// the others shrink and fade with distance. When the line changes the whole list glides
/// up, computed from the time since the line began, so no state is kept between frames.
public struct ScrollingListStyle: LyricStyle {
    public let name = "Scrolling List"

    /// Seconds the list takes to glide to the next line.
    private let glide = 0.35
    /// Lines beyond this many slots from the anchor are not drawn.
    private let reach = 2.4

    public init() {}

    public func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem] {
        guard !frame.lines.isEmpty else { return [] }
        let maxWidth = viewport.width * config.maxWidthFraction
        let centerY = viewport.height * (1 - config.anchorY)
        let slot = Double(measurer.lineHeight(font: config.font) * CGFloat(config.lineSpacing)) * 0.92

        // `camera` is the list position in line units; the current line sits at `camera + 1`
        // until the glide finishes, so it arrives from one slot below.
        let current = frame.cursor.lineIndex ?? -1
        let glideDone = current >= 0 ? StyleKit.smooth((frame.position - frame.lines[current].start) / glide) : 0
        let camera = Double(current) - 1 + glideDone

        // Before the first line the list fades in as the song approaches it.
        var intro: Float = 1
        if current < 0, let first = frame.lines.first {
            let lead = max(0, first.start - frame.position)
            intro = lead < 4 ? Float(1 - lead / 4) : 0
        }
        guard intro > 0 else { return [] }

        var items: [DrawItem] = []
        for i in max(0, current - 3)...min(frame.lines.count - 1, current + 3) {
            let d = Double(i) - camera
            guard abs(d) <= reach else { continue }
            let line = frame.lines[i]
            guard !line.isInstrumentalGap else { continue }

            let near = min(1, abs(d))
            let scale = Float(1 - 0.4 * near - 0.1 * max(0, min(abs(d), 2) - 1))
            let opacity = Float(max(0, 1 - 0.42 * abs(d))) * intro
            let y = centerY + CGFloat(d * slot)

            if i == current, !line.words.isEmpty {
                items += currentLine(line, index: i, frame: frame, y: y, scale: scale, opacity: opacity,
                                     viewportWidth: viewport.width, maxWidth: maxWidth, config: config, measurer: measurer)
            } else {
                // Upcoming lines share the current line's unsung color so a line arriving at the anchor
                // does not change color; sung lines keep the highlight and fade from it.
                let color = i < current
                    ? config.highlightColor.scaledAlpha(Float(StyleKit.lerp(1, 0.45, near)))
                    : config.baseColor.scaledAlpha(Float(StyleKit.lerp(1, 0.6, near)))
                items.append(StyleKit.singleLine(
                    line.text, font: config.font, center: CGPoint(x: viewport.width / 2, y: y), maxWidth: maxWidth,
                    measurer: measurer, base: color, highlight: color, progress: i < current ? 1 : 0,
                    opacity: opacity, config: config, scale: scale, lineIndex: i))
            }
        }
        return items
    }

    private func currentLine(_ line: LyricLine, index: Int, frame: LyricsFrame, y: CGFloat, scale: Float, opacity: Float,
                             viewportWidth: CGFloat, maxWidth: CGFloat, config: OverlayConfig,
                             measurer: TextMeasuring) -> [DrawItem] {
        let row = StyleKit.fittedRow(words: line.words.map(\.text), font: config.font, viewportWidth: viewportWidth,
                                     centerY: y, maxWidth: maxWidth, measurer: measurer)
        let centerX = viewportWidth / 2
        return row.words.map { p in
            DrawItem(
                text: p.text, font: row.font,
                // Words keep their spacing relative to the line's center as the line scales.
                center: CGPoint(x: centerX + (p.center.x - centerX) * CGFloat(scale), y: y),
                size: CGSize(width: p.width, height: row.rowHeight),
                baseColor: config.baseColor, highlightColor: config.highlightColor,
                glowColor: config.glowColor, glow: config.glow * scale,
                progress: StyleKit.wordProgress(p.index, frame.cursor),
                opacity: opacity, shadow: config.shadow, scale: scale,
                lineIndex: index, wordIndex: p.index)
        }
    }
}
