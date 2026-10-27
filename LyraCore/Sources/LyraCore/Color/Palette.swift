import Foundation

/// Colors pulled from a track's artwork.
public struct Palette: Equatable, Codable, Sendable {
    /// The most common color in the artwork.
    public var dominant: RGBA
    /// The most vivid color that covers a meaningful part of the artwork.
    public var accent: RGBA
    /// A second color clearly different from the other two.
    public var secondary: RGBA
    /// Every cluster found, most common first.
    public var swatches: [RGBA]
    /// True when the artwork is dark overall (mean luma below 0.5).
    public var isDark: Bool

    public init(dominant: RGBA, accent: RGBA, secondary: RGBA, swatches: [RGBA], isDark: Bool) {
        self.dominant = dominant
        self.accent = accent
        self.secondary = secondary
        self.swatches = swatches
        self.isDark = isDark
    }

    /// Lightness floor for colors that must glow against a dark background.
    public static let minimumGlowLightness = 62.0

    /// `accent` lifted to a lightness that glows on dark backgrounds; hue is kept.
    public var lightPrimary: RGBA { ColorMath.lifted(accent, minL: Self.minimumGlowLightness) }
    public var lightSecondary: RGBA { ColorMath.lifted(secondary, minL: Self.minimumGlowLightness) }
}
