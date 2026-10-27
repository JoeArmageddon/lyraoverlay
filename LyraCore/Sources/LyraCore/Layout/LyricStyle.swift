import Foundation
import CoreGraphics

/// Measures text without knowing how it will be drawn, so layout stays testable.
public protocol TextMeasuring: Sendable {
    func width(of text: String, font: FontSpec) -> CGFloat
    func lineHeight(font: FontSpec) -> CGFloat
}

/// One piece of text for the renderer to draw. Coordinates are points in the view,
/// origin top-left, y down.
public struct DrawItem: Equatable, Sendable {
    public var text: String
    public var font: FontSpec
    public var center: CGPoint
    public var size: CGSize
    public var baseColor: RGBA
    public var highlightColor: RGBA
    public var glowColor: RGBA
    public var glow: Float
    /// 0...1: how much of the text, left to right, is already sung.
    public var progress: Float
    public var opacity: Float
    /// 0...1 strength of the soft dark halo that keeps text readable on bright backgrounds.
    public var shadow: Float
    /// Uniform scale about `center`; the text is rasterized once at `font` size and drawn larger or smaller.
    public var scale: Float
    /// Index of the lyric line this item belongs to; nil for items that belong to none. Entrance and
    /// exit animations act only on the current line, so previews and neighbours must carry their own.
    public var lineIndex: Int?
    /// Index of the word within its line; 0 for items that are a whole line.
    public var wordIndex: Int
    /// 0...1 softness: 0 is sharp, 1 is fully defocused. Used by the blur entrance and exit.
    public var blur: Float
    /// True for the one word a style singles out as the hero of the line. Finishing effects (the
    /// anamorphic flare) aim at it; styles that don't pick a word leave it false.
    public var isEmphasis: Bool

    public init(text: String, font: FontSpec, center: CGPoint, size: CGSize, baseColor: RGBA, highlightColor: RGBA,
                glowColor: RGBA, glow: Float, progress: Float, opacity: Float, shadow: Float = 0, scale: Float = 1,
                lineIndex: Int? = nil, wordIndex: Int = 0, blur: Float = 0, isEmphasis: Bool = false) {
        self.isEmphasis = isEmphasis
        self.shadow = shadow
        self.scale = scale
        self.lineIndex = lineIndex
        self.wordIndex = wordIndex
        self.blur = blur
        self.text = text
        self.font = font
        self.center = center
        self.size = size
        self.baseColor = baseColor
        self.highlightColor = highlightColor
        self.glowColor = glowColor
        self.glow = glow
        self.progress = progress
        self.opacity = opacity
    }
}

/// What the style needs to know about the song at one instant.
public struct LyricsFrame: Sendable {
    public var lines: [LyricLine]
    public var cursor: CursorState
    /// Lyrics-clock position in seconds, already offset-corrected.
    public var position: TimeInterval
    /// 0...1 beat pulse from the audio analysis (1 on a beat, decaying), 0 when there is no audio.
    /// Styles may use it for punch and camera shake; ignoring it is always fine.
    public var beat: Float
    /// 0...1 smoothed low-frequency energy, 0 when there is no audio.
    public var bass: Float

    public init(lines: [LyricLine], cursor: CursorState, position: TimeInterval, beat: Float = 0, bass: Float = 0) {
        self.lines = lines
        self.cursor = cursor
        self.position = position
        self.beat = beat
        self.bass = bass
    }
}

public protocol LyricStyle: Sendable {
    var name: String { get }
    func layout(_ frame: LyricsFrame, viewport: CGSize, config: OverlayConfig, measurer: TextMeasuring) -> [DrawItem]
}
