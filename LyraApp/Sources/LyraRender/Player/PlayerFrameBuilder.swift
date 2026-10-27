import Foundation
import CoreGraphics
import LyraCore

/// The per-frame decisions of the player window, kept free of views so they can be tested:
/// how big the lyrics are, where they sit, and where the border's colors come from.
enum PlayerFrameBuilder {
    /// The window width at which lyric sizes are as configured; wider windows scale the text up.
    static let referenceWidth: CGFloat = 1440

    /// Lyric size multiplier for a window `viewportWidth` points wide.
    static func fontScale(viewportWidth: CGFloat, lyricsScale: Double) -> Double {
        max(0.25, Double(viewportWidth / referenceWidth)) * lyricsScale
    }

    /// The overlay config adapted to the player: album colors applied, text scaled with the window,
    /// and the current line centered vertically.
    static func lyricConfig(base: OverlayConfig, albumPalette: Palette?, useArtworkColors: Bool,
                            viewportWidth: CGFloat, lyricsScale: Double) -> OverlayConfig {
        var config = ThemeResolver.resolve(base, palette: albumPalette, useArtworkColors: useArtworkColors)
        config.font = config.font.withSize(base.font.size * fontScale(viewportWidth: viewportWidth, lyricsScale: lyricsScale))
        config.anchorY = 0.5
        return config
    }

    /// Whose colors the border should wear: the background's when it follows the background and
    /// has colors, otherwise the album's, otherwise none (the effect's own defaults).
    static func borderSource(background: Palette?, album: Palette?, followBackground: Bool) -> Palette? {
        if followBackground, let background { return background }
        return album
    }

    static func borderColors(from palette: Palette?) -> (primary: RGBA, secondary: RGBA) {
        guard let palette else { return (RimGlowEffect.defaultPrimary, RimGlowEffect.defaultSecondary) }
        return (palette.lightPrimary, palette.lightSecondary)
    }

    /// The border is configured in points for a 1440-wide window; scale its thickness with the window
    /// (within limits), so it neither vanishes on a big screen nor swallows a small window.
    static func borderConfig(_ config: LightConfig, viewportWidth: CGFloat) -> LightConfig {
        var scaled = config
        let factor = min(2, max(0.5, Double(viewportWidth / referenceWidth)))
        scaled.thickness = config.thickness * factor
        return scaled
    }

    // MARK: - Cinema

    /// The area lyrics are laid out in: the whole view, or the picture inside letterbox bars.
    static func lyricRegion(cinema: CinemaSettings, viewport: CGSize) -> CGRect {
        CinemaEffect.pictureRect(settings: cinema, viewport: viewport)
    }

    /// Moves laid-out items down by `origin`, so text computed for the picture rect sits inside the bars.
    /// With no offset the very same array comes back, which keeps cinema-off output untouched.
    static func shifted(_ items: [DrawItem], by origin: CGPoint) -> [DrawItem] {
        guard origin != .zero else { return items }
        return items.map { item in
            var moved = item
            moved.center = CGPoint(x: item.center.x + origin.x, y: item.center.y + origin.y)
            return moved
        }
    }

    /// The frame handed to the style, with the beat and bass of the music when audio is being captured.
    static func lyricsFrame(lines: [LyricLine], cursor: CursorState, position: TimeInterval, features: AudioFeatures?) -> LyricsFrame {
        LyricsFrame(lines: lines, cursor: cursor, position: position, beat: features?.beat ?? 0, bass: features?.bass ?? 0)
    }

    /// Where the hero word is, so the flare can cross it. Words that are still invisible don't count.
    static func emphasisCenter(in items: [DrawItem]) -> CGPoint? {
        items.first { $0.isEmphasis && $0.opacity > 0.05 }?.center
    }

    static func lightParams(effect: LightEffect, features: AudioFeatures?, palette: Palette?, config: LightConfig,
                            viewportWidth: CGFloat, time: Double) -> LightParams? {
        let colors = borderColors(from: palette)
        let input = LightInput(features: features, primary: colors.primary, secondary: colors.secondary, time: time)
        return effect.params(input, config: borderConfig(config, viewportWidth: viewportWidth))
    }
}

/// Applies a letter-case transform to a lyrics document once and reuses it, because the transform
/// touches every word and the window asks for lyrics every frame.
final class LyricsCaseCache {
    private var cached: (key: String, document: LyricsDocument)?

    func document(_ doc: LyricsDocument, trackKey: String, textCase: TextCase) -> LyricsDocument {
        if textCase == .asWritten { return doc }
        let key = "\(trackKey)|\(textCase.rawValue)"
        if let cached, cached.key == key { return cached.document }
        let mapped = doc.applying(textCase)
        cached = (key, mapped)
        return mapped
    }
}
