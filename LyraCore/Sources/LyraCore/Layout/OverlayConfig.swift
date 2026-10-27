import Foundation
import CoreGraphics

public struct RGBA: Equatable, Hashable, Codable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public func withAlpha(_ alpha: Float) -> RGBA { RGBA(r, g, b, alpha) }
    public func scaledAlpha(_ k: Float) -> RGBA { RGBA(r, g, b, a * k) }

    public static let white = RGBA(1, 1, 1, 1)
}

/// A font by family name. "System" is the macOS system font; any other value is
/// looked up by family or PostScript name and falls back to the system font.
public struct FontSpec: Hashable, Codable, Sendable {
    public var family: String
    public var size: Double
    /// NSFont.Weight raw value: -1 (ultra light) ... 0 (regular) ... 1 (black). Used for the system font.
    public var weight: Double
    /// Letter spacing in em: 0.05 adds 5% of the font size after every character, negative tightens.
    public var tracking: Double
    public var italic: Bool

    public init(family: String = "System", size: Double, weight: Double = 0, tracking: Double = 0, italic: Bool = false) {
        self.family = family
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.italic = italic
    }

    /// Tolerant: files saved before tracking and italic existed still decode.
    public init(from decoder: Decoder) throws {
        self.init(size: 46)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = c.get(.family, family)
        size = c.get(.size, size)
        weight = c.get(.weight, weight)
        tracking = c.get(.tracking, tracking)
        italic = c.get(.italic, italic)
    }

    public func withSize(_ s: Double) -> FontSpec {
        FontSpec(family: family, size: s, weight: weight, tracking: tracking, italic: italic)
    }
}

public struct OverlayConfig: Equatable, Codable, Sendable {
    public var font = FontSpec(family: "System", size: 46, weight: 0.4)
    public var textCase = TextCase.asWritten
    /// Words not yet sung.
    public var baseColor = RGBA(1, 1, 1, 0.38)
    /// Words already sung.
    public var highlightColor = RGBA(1, 1, 1, 1)
    public var glowColor = RGBA(0.55, 0.75, 1, 1)
    /// 0 disables the glow.
    public var glow: Float = 0.6
    /// 0 disables the dark halo behind text.
    public var shadow: Float = 0.5

    /// Size of the preview line relative to the current line.
    public var secondaryScale = 0.52
    public var secondaryOpacity: Float = 0.55
    public var showNextLine = true

    public var maxWidthFraction = 0.78
    /// Vertical position of the current line's center, as a fraction of the height from the bottom.
    public var anchorY = 0.16
    public var lineSpacing = 1.22

    /// Seconds. Positive shows lyrics later, negative earlier; tunes sync per setup.
    public var latencyOffset = 0.0
    public var fadeInDuration = 0.25
    /// How long a finished line stays before fading out, and how long that fade takes.
    public var lingerAfterSung = 1.5
    public var fadeOutDuration = 0.8

    /// How lines arrive and leave, on top of each style's baseline fade.
    public var entrance = EntranceAnimation.fade
    public var exit = ExitAnimation.fade
    /// Seconds the entrance takes.
    public var entranceDuration = 0.45
    /// Seconds between consecutive words starting their entrance (cascade-style effects).
    public var entranceStagger = 0.05

    public init() {}

    /// Tolerant: any missing or malformed key keeps its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        font = c.get(.font, font)
        textCase = c.get(.textCase, textCase)
        baseColor = c.get(.baseColor, baseColor)
        highlightColor = c.get(.highlightColor, highlightColor)
        glowColor = c.get(.glowColor, glowColor)
        glow = c.get(.glow, glow)
        shadow = c.get(.shadow, shadow)
        secondaryScale = c.get(.secondaryScale, secondaryScale)
        secondaryOpacity = c.get(.secondaryOpacity, secondaryOpacity)
        showNextLine = c.get(.showNextLine, showNextLine)
        maxWidthFraction = c.get(.maxWidthFraction, maxWidthFraction)
        anchorY = c.get(.anchorY, anchorY)
        lineSpacing = c.get(.lineSpacing, lineSpacing)
        latencyOffset = c.get(.latencyOffset, latencyOffset)
        fadeInDuration = c.get(.fadeInDuration, fadeInDuration)
        lingerAfterSung = c.get(.lingerAfterSung, lingerAfterSung)
        fadeOutDuration = c.get(.fadeOutDuration, fadeOutDuration)
        entrance = c.get(.entrance, entrance)
        exit = c.get(.exit, exit)
        entranceDuration = c.get(.entranceDuration, entranceDuration)
        entranceStagger = c.get(.entranceStagger, entranceStagger)
    }
}
