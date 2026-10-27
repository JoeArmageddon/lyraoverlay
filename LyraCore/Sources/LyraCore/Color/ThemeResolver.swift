import Foundation

/// Applies artwork colors to a config. Pure: same inputs, same output.
public enum ThemeResolver {
    /// How far the sung-word color leans toward the artwork accent (18%), and how far the
    /// unsung color leans toward the dominant color (20%).
    static let highlightTint: Float = 0.18
    static let baseTint: Float = 0.20

    /// With a palette and `useArtworkColors`, the glow takes the (lightened) accent, sung
    /// words become near-white with a hint of it, and unsung words a hint of the dominant
    /// color at their existing opacity. Otherwise `config` comes back unchanged.
    public static func resolve(_ config: OverlayConfig, palette: Palette?, useArtworkColors: Bool) -> OverlayConfig {
        guard useArtworkColors, let palette else { return config }
        let glow = palette.lightPrimary

        var themed = config
        themed.glowColor = glow
        themed.highlightColor = mix(.white, glow, highlightTint, alpha: 1)
        themed.baseColor = mix(.white, palette.dominant, baseTint, alpha: config.baseColor.a)
        return themed
    }

    /// Linear blend of RGB from `a` toward `b` by `t`, with the given alpha.
    static func mix(_ a: RGBA, _ b: RGBA, _ t: Float, alpha: Float) -> RGBA {
        RGBA(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, alpha)
    }
}
