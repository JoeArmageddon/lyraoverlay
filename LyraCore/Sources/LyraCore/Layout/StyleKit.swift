import Foundation
import CoreGraphics

/// Layout helpers shared by the lyric styles. `KaraokeLineStyle` keeps its own private
/// copies so that file never needs to change when a style does.
enum StyleKit {
    struct Placed {
        var index: Int
        var text: String
        var width: CGFloat
        var center: CGPoint
    }

    struct Block {
        var words: [Placed]
        var rowHeight: CGFloat
        /// Vertical extent of the whole block, rows included.
        var top: CGFloat
        var bottom: CGFloat
    }

    static func smooth(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * min(1, max(0, t)) }

    /// 1 for words already sung (or once the line is finished), the wipe progress for the
    /// word being sung, 0 for the rest.
    static func wordProgress(_ n: Int, _ cursor: CursorState) -> Float {
        guard cursor.isSinging, let current = cursor.wordIndex else { return 1 }
        if n < current { return 1 }
        if n == current { return Float(cursor.wordProgress) }
        return 0
    }

    /// Fades in at line start, holds, then fades out some time after the line is sung.
    static func lineOpacity(_ line: LyricLine, position: TimeInterval, config: OverlayConfig) -> Float {
        let fadeIn = config.fadeInDuration > 0 ? smooth((position - line.start) / config.fadeInDuration) : 1
        let fadeOutStart = line.sungEnd + config.lingerAfterSung
        let fadeOut = config.fadeOutDuration > 0 ? 1 - smooth((position - fadeOutStart) / config.fadeOutDuration) : 1
        return Float(min(fadeIn, fadeOut))
    }

    /// 0 before a word starts, then a quick rise and exponential settle: the shape of a pop.
    static func popEnvelope(_ age: Double) -> Double {
        guard age > 0 else { return 0 }
        return min(1, age / 0.04) * exp(-6 * age)
    }

    /// Wrapped, centered rows around `centerY`, one `Placed` per word in reading order.
    static func block(words: [String], font: FontSpec, viewport: CGSize, centerY: CGFloat,
                      maxWidth: CGFloat, lineSpacing: Double, measurer: TextMeasuring) -> Block {
        let rows = KaraokeLineStyle().wrap(words, font: font, maxWidth: maxWidth, measurer: measurer)
        let rowHeight = measurer.lineHeight(font: font) * CGFloat(lineSpacing)
        let top = centerY - rowHeight * CGFloat(max(0, rows.count - 1)) / 2
        var placed: [Placed] = []
        var index = 0
        for (r, row) in rows.enumerated() {
            var x = (viewport.width - row.width) / 2
            let y = top + rowHeight * CGFloat(r)
            for (text, width) in zip(row.words, row.widths) {
                placed.append(Placed(index: index, text: text, width: width, center: CGPoint(x: x + width / 2, y: y)))
                x += width + row.space
                index += 1
            }
        }
        return Block(words: placed, rowHeight: rowHeight,
                     top: top - rowHeight / 2, bottom: top + rowHeight * CGFloat(max(0, rows.count - 1)) + rowHeight / 2)
    }

    /// All words on one row, with the font shrunk until the row fits `maxWidth`. The shrink
    /// depends only on the text, so the rasterized font is constant for a given line.
    static func fittedRow(words: [String], font: FontSpec, viewportWidth: CGFloat, centerY: CGFloat,
                          maxWidth: CGFloat, measurer: TextMeasuring) -> (font: FontSpec, words: [Placed], rowHeight: CGFloat) {
        func measure(_ f: FontSpec) -> (widths: [CGFloat], space: CGFloat, total: CGFloat) {
            let widths = words.map { measurer.width(of: $0, font: f) }
            let space = CGFloat(f.size) * 0.28
            return (widths, space, widths.reduce(0, +) + space * CGFloat(max(0, words.count - 1)))
        }
        var f = font
        var m = measure(f)
        if m.total > maxWidth, m.total > 0 {
            f = font.withSize(font.size * Double(maxWidth / m.total))
            m = measure(f)
        }
        var x = (viewportWidth - m.total) / 2
        var placed: [Placed] = []
        for (i, (text, width)) in zip(words, m.widths).enumerated() {
            placed.append(Placed(index: i, text: text, width: width, center: CGPoint(x: x + width / 2, y: centerY)))
            x += width + m.space
        }
        return (f, placed, measurer.lineHeight(font: f))
    }

    /// A single dimmed line, shrunk to fit.
    static func singleLine(_ text: String, font: FontSpec, center: CGPoint, maxWidth: CGFloat, measurer: TextMeasuring,
                           base: RGBA, highlight: RGBA, progress: Float, opacity: Float, config: OverlayConfig,
                           scale: Float = 1, lineIndex: Int? = nil, wordIndex: Int = 0) -> DrawItem {
        var f = font
        var width = measurer.width(of: text, font: f)
        if width > maxWidth, width > 0 {
            f = f.withSize(f.size * Double(maxWidth / width))
            width = measurer.width(of: text, font: f)
        }
        return DrawItem(text: text, font: f, center: center,
                        size: CGSize(width: width, height: measurer.lineHeight(font: f)),
                        baseColor: base, highlightColor: highlight, glowColor: config.glowColor, glow: 0,
                        progress: progress, opacity: opacity, shadow: config.shadow, scale: scale,
                        lineIndex: lineIndex, wordIndex: wordIndex)
    }
}
