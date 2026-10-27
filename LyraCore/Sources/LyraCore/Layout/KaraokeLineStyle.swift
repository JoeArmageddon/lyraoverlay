import Foundation
import CoreGraphics

/// The current line, centered and wrapped, with each word wiping from the base
/// color to the highlight as it is sung, plus a smaller preview of the next line.
public struct KaraokeLineStyle: LyricStyle {
    public let name = "Karaoke Line"

    public init() {}

    public func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem] {
        guard !frame.lines.isEmpty else { return [] }
        let maxWidth = viewport.width * config.maxWidthFraction
        let centerY = viewport.height * (1 - config.anchorY)
        var items: [DrawItem] = []

        guard let index = frame.cursor.lineIndex else {
            // Before the first line: preview it where the current line will appear.
            if config.showNextLine, let first = frame.lines.first, !first.text.isEmpty {
                let lead = max(0, first.start - frame.position)
                let fade = lead < 4 ? Float(1 - lead / 4) : 0
                items += previewItems(first.text, lineIndex: 0, centerY: centerY, viewport: viewport, config: config, measurer: measurer, opacity: fade)
            }
            return items
        }

        let line = frame.lines[index]
        var blockBottom = centerY

        if !line.isInstrumentalGap, !line.words.isEmpty {
            let opacity = lineOpacity(line, position: frame.position, config: config)
            if opacity > 0 {
                let rows = wrap(line.words.map(\.text), font: config.font, maxWidth: maxWidth, measurer: measurer)
                let rowHeight = measurer.lineHeight(font: config.font) * config.lineSpacing
                let top = centerY - rowHeight * CGFloat(rows.count - 1) / 2
                var wordIndex = 0
                for (r, row) in rows.enumerated() {
                    var x = (viewport.width - row.width) / 2
                    let y = top + rowHeight * CGFloat(r)
                    for (text, width) in zip(row.words, row.widths) {
                        items.append(DrawItem(
                            text: text, font: config.font,
                            center: CGPoint(x: x + width / 2, y: y),
                            size: CGSize(width: width, height: rowHeight),
                            baseColor: config.baseColor, highlightColor: config.highlightColor,
                            glowColor: config.glowColor, glow: config.glow,
                            progress: wordProgress(wordIndex, frame.cursor),
                            opacity: opacity, shadow: config.shadow,
                            lineIndex: index, wordIndex: wordIndex))
                        x += width + row.space
                        wordIndex += 1
                    }
                }
                blockBottom = top + rowHeight * CGFloat(rows.count - 1) + rowHeight / 2
            }
        }

        if config.showNextLine, index + 1 < frame.lines.count {
            let next = frame.lines[index + 1]
            if !next.text.isEmpty {
                let secondaryHeight = measurer.lineHeight(font: config.font.withSize(config.font.size * config.secondaryScale))
                let y = blockBottom + secondaryHeight * 0.9
                items += previewItems(next.text, lineIndex: index + 1, centerY: y, viewport: viewport, config: config, measurer: measurer, opacity: 1)
            }
        }
        return items
    }

    // MARK: - Pieces

    private func wordProgress(_ n: Int, _ cursor: CursorState) -> Float {
        guard cursor.isSinging, let current = cursor.wordIndex else { return 1 }   // line finished: all sung
        if n < current { return 1 }
        if n == current { return Float(cursor.wordProgress) }
        return 0
    }

    /// Fades in at line start, holds, then fades out some time after the line is sung.
    private func lineOpacity(_ line: LyricLine, position: TimeInterval, config: OverlayConfig) -> Float {
        let fadeIn = config.fadeInDuration > 0 ? smooth((position - line.start) / config.fadeInDuration) : 1
        let fadeOutStart = line.sungEnd + config.lingerAfterSung
        let fadeOut = config.fadeOutDuration > 0 ? 1 - smooth((position - fadeOutStart) / config.fadeOutDuration) : 1
        return Float(min(fadeIn, fadeOut))
    }

    private func smooth(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    /// A dimmed single line, shrunk to fit if it is wider than the allowed width.
    private func previewItems(_ text: String, lineIndex: Int, centerY: CGFloat, viewport: CGSize, config: OverlayConfig,
                              measurer: TextMeasuring, opacity: Float) -> [DrawItem] {
        guard opacity > 0 else { return [] }
        let dim = config.highlightColor.scaledAlpha(config.secondaryOpacity)
        var font = config.font.withSize(config.font.size * config.secondaryScale)
        var width = measurer.width(of: text, font: font)
        let maxWidth = viewport.width * config.maxWidthFraction
        if width > maxWidth {
            font = font.withSize(font.size * Double(maxWidth / width))
            width = measurer.width(of: text, font: font)
        }
        return [DrawItem(
            text: text, font: font,
            center: CGPoint(x: viewport.width / 2, y: centerY),
            size: CGSize(width: width, height: measurer.lineHeight(font: font)),
            baseColor: dim, highlightColor: dim,
            glowColor: config.glowColor, glow: 0, progress: 0, opacity: opacity, shadow: config.shadow,
            lineIndex: lineIndex)]
    }

    // MARK: - Wrapping

    struct Row {
        var words: [String] = []
        var widths: [CGFloat] = []
        var space: CGFloat
        var width: CGFloat {
            widths.reduce(0, +) + space * CGFloat(max(0, words.count - 1))
        }
    }

    /// Greedy line breaking. A single word wider than `maxWidth` gets its own row.
    func wrap(_ words: [String], font: FontSpec, maxWidth: CGFloat, measurer: TextMeasuring) -> [Row] {
        let space = CGFloat(font.size) * 0.28
        var rows: [Row] = []
        var row = Row(space: space)
        for word in words {
            let w = measurer.width(of: word, font: font)
            if !row.words.isEmpty, row.width + space + w > maxWidth {
                rows.append(row)
                row = Row(space: space)
            }
            row.words.append(word)
            row.widths.append(w)
        }
        if !row.words.isEmpty { rows.append(row) }
        return rows
    }
}
