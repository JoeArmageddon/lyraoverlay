import Foundation
import CoreGraphics

/// The word being sung fills the screen; the whole line sits small underneath with the sung
/// part brighter. The previous word shrinks away as the next one pops in.
public struct FocusStyle: LyricStyle {
    public let name = "Word Focus"

    /// Size of the big word relative to the configured font.
    private let bigFactor = 2.1
    /// Seconds the previous word takes to leave.
    private let leaveTime = 0.2

    public init() {}

    public func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem] {
        guard !frame.lines.isEmpty, let index = frame.cursor.lineIndex else { return [] }
        let line = frame.lines[index]
        guard !line.isInstrumentalGap, !line.words.isEmpty else { return [] }

        let opacity = StyleKit.lineOpacity(line, position: frame.position, config: config)
        guard opacity > 0 else { return [] }

        let maxWidth = viewport.width * config.maxWidthFraction
        let bigFont = config.font.withSize(config.font.size * bigFactor)
        let bigHeight = measurer.lineHeight(font: bigFont)
        let centerY = viewport.height * (1 - config.anchorY)
        var items: [DrawItem] = []

        // The big word, only while a word is actually being sung.
        if frame.cursor.isSinging, let n = frame.cursor.wordIndex {
            let word = line.words[n]
            let age = frame.position - word.start
            let enter = Float(StyleKit.smooth(age / 0.08))
            let scale = Float(1 + 0.22 * StyleKit.popEnvelope(age))
            items.append(StyleKit.singleLine(
                word.text, font: bigFont, center: CGPoint(x: viewport.width / 2, y: centerY), maxWidth: maxWidth,
                // The big word's unsung part is brighter than the small line's, so it reads at a glance.
                measurer: measurer, base: config.baseColor.withAlpha(min(1, config.baseColor.a * 2)), highlight: config.highlightColor,
                progress: Float(frame.cursor.wordProgress), opacity: opacity * enter, config: config, scale: scale,
                lineIndex: index, wordIndex: n)
                .with { $0.glow = config.glow })

            // The word before it, shrinking and fading as the new one arrives.
            if n > 0 {
                let leave = StyleKit.smooth(age / leaveTime)
                if leave < 1 {
                    let previous = line.words[n - 1]
                    var ghost = StyleKit.singleLine(
                        previous.text, font: bigFont,
                        center: CGPoint(x: viewport.width / 2, y: centerY - CGFloat(leave) * bigHeight * 0.25),
                        maxWidth: maxWidth, measurer: measurer, base: config.highlightColor, highlight: config.highlightColor,
                        progress: 1, opacity: opacity * Float(1 - leave), config: config,
                        scale: Float(1 - 0.25 * leave), lineIndex: index, wordIndex: n - 1)
                    ghost.glow = 0
                    items.append(ghost)
                }
            }
        }

        // The whole line, small, below the big word. Sung words are brighter than the rest.
        let smallFont = config.font.withSize(config.font.size * config.secondaryScale)
        let rowY = centerY + bigHeight * 0.62 + measurer.lineHeight(font: smallFont) * 0.4
        let row = StyleKit.fittedRow(words: line.words.map(\.text), font: smallFont, viewportWidth: viewport.width,
                                     centerY: rowY, maxWidth: maxWidth, measurer: measurer)
        let dimBase = config.baseColor.scaledAlpha(0.8)
        let dimHighlight = config.highlightColor.scaledAlpha(0.85)
        for p in row.words {
            items.append(DrawItem(
                text: p.text, font: row.font, center: p.center, size: CGSize(width: p.width, height: row.rowHeight),
                baseColor: dimBase, highlightColor: dimHighlight, glowColor: config.glowColor, glow: 0,
                progress: StyleKit.wordProgress(p.index, frame.cursor), opacity: opacity, shadow: config.shadow,
                lineIndex: index, wordIndex: p.index))
        }
        return items
    }
}

private extension DrawItem {
    /// Copy with a change applied, to keep construction expressions readable.
    func with(_ change: (inout DrawItem) -> Void) -> DrawItem {
        var copy = self
        change(&copy)
        return copy
    }
}
