import Foundation

/// A complete look: lyric style, text appearance and lighting, bundled as one shareable unit.
/// Sync offset is deliberately not part of a theme: it depends on the user's setup, not the look.
public struct Theme: Identifiable, Equatable, Codable, Sendable {
    /// Bump when the file format changes incompatibly.
    public static let formatVersion = 1

    public var id: String
    public var name: String
    /// A `LyricStyles` id such as "karaoke"; unknown ids fall back to the default style.
    public var styleID: String
    public var overlay: OverlayConfig
    public var lights: LightConfig
    public var useArtworkColors: Bool

    public init(id: String, name: String, styleID: String = "karaoke", overlay: OverlayConfig = OverlayConfig(),
                lights: LightConfig = LightConfig(), useArtworkColors: Bool = true) {
        self.id = id
        self.name = name
        self.styleID = styleID
        self.overlay = overlay
        self.lights = lights
        self.useArtworkColors = useArtworkColors
    }

    /// Tolerant: a missing or malformed field keeps its default, so shared files from
    /// other versions still load. Identity fields have no sensible default and are required.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        styleID = c.get(.styleID, "karaoke")
        overlay = c.get(.overlay, OverlayConfig())
        lights = c.get(.lights, LightConfig())
        useArtworkColors = c.get(.useArtworkColors, true)
    }

    /// The overlay config to use when applying this theme: the theme's look with the
    /// user's current sync offset kept.
    public func overlay(preservingSyncFrom current: OverlayConfig) -> OverlayConfig {
        var o = overlay
        o.latencyOffset = current.latencyOffset
        return o
    }

    /// Whether the given settings are this theme, ignoring the sync offset.
    public func matches(styleID: String, overlay current: OverlayConfig, lights currentLights: LightConfig, useArtworkColors current_: Bool) -> Bool {
        self.styleID == styleID
            && overlay(preservingSyncFrom: current) == current
            && lights == currentLights
            && useArtworkColors == current_
    }
}

/// On-disk wrapper so shared theme files carry a version number.
struct ThemeFile: Codable {
    var version: Int
    var theme: Theme
}

public enum BuiltInThemes {
    /// Stable ids: saved settings refer to these.
    public static let classicID = "builtin.classic"

    /// The original six come first (their ids are referenced by saved settings), then the rest.
    /// Every theme has its own typeface, so no two share a font family.
    public static let all: [Theme] = [classic, neon, minimal, terminal, cinema, pulse] + collection

    public static let classic = Theme(id: classicID, name: "Classic")

    public static let neon: Theme = {
        var o = OverlayConfig()
        o.font = FontSpec(family: "LyraNeonTube-Regular", size: 50)
        o.entrance = .zoomIn
        o.exit = .shrink
        o.entranceDuration = 0.35
        o.highlightColor = RGBA(1, 0.95, 1, 1)
        o.baseColor = RGBA(1, 1, 1, 0.3)
        o.glowColor = RGBA(1, 0.2, 0.85, 1)
        o.glow = 1.0
        o.shadow = 0.15
        var l = LightConfig()
        l.intensity = 1.0
        l.thickness = 40
        l.beatReactivity = 1.0
        l.useArtworkColors = false
        l.primary = RGBA(1, 0.2, 0.85)
        l.secondary = RGBA(0.1, 0.9, 1)
        return Theme(id: "builtin.neon", name: "Neon", styleID: "pop", overlay: o, lights: l, useArtworkColors: false)
    }()

    public static let minimal: Theme = {
        var o = OverlayConfig()
        o.font = FontSpec(family: "HelveticaNeue-Light", size: 40, weight: 0, tracking: 0.06)
        o.entranceDuration = 0.6
        o.baseColor = RGBA(1, 1, 1, 0.35)
        o.glow = 0
        o.shadow = 0.35
        o.showNextLine = false
        var l = LightConfig()
        l.enabled = false
        return Theme(id: "builtin.minimal", name: "Minimal", styleID: "karaoke", overlay: o, lights: l)
    }()

    public static let terminal: Theme = {
        var o = OverlayConfig()
        o.font = FontSpec(family: "Menlo-Bold", size: 38, weight: 0, tracking: 0.04)
        o.textCase = .upper
        o.entrance = .none
        o.exit = .none
        o.highlightColor = RGBA(0.45, 1, 0.6, 1)
        o.baseColor = RGBA(0.45, 1, 0.6, 0.0)
        o.glowColor = RGBA(0.2, 1, 0.45, 1)
        o.glow = 0.7
        o.anchorY = 0.2
        var l = LightConfig()
        l.enabled = false
        return Theme(id: "builtin.terminal", name: "Terminal", styleID: "typewriter", overlay: o, lights: l, useArtworkColors: false)
    }()

    public static let cinema: Theme = {
        var o = OverlayConfig()
        o.font = FontSpec(family: "Georgia-Bold", size: 48, weight: 0, italic: true)
        o.entrance = .rise
        o.entranceDuration = 0.7
        o.highlightColor = RGBA(1, 0.93, 0.8, 1)
        o.baseColor = RGBA(1, 0.93, 0.8, 0.35)
        o.glowColor = RGBA(1, 0.65, 0.25, 1)
        o.glow = 0.5
        var l = LightConfig()
        l.thickness = 20
        l.intensity = 0.6
        l.beatReactivity = 0.4
        l.primary = RGBA(1, 0.65, 0.25)
        l.secondary = RGBA(1, 0.4, 0.2)
        l.useArtworkColors = false
        return Theme(id: "builtin.cinema", name: "Cinema", styleID: "scroll", overlay: o, lights: l, useArtworkColors: false)
    }()

    public static let pulse: Theme = {
        var o = OverlayConfig()
        o.font = FontSpec(family: "Futura-Bold", size: 50)
        o.entrance = .cascade
        o.exit = .rise
        o.entranceDuration = 0.5
        o.entranceStagger = 0.07
        o.glow = 0.8
        var l = LightConfig()
        l.intensity = 1.0
        l.thickness = 48
        l.beatReactivity = 1.0
        l.idleGlow = 0.12
        l.driftSpeed = 0.12
        return Theme(id: "builtin.pulse", name: "Pulse", styleID: "wave", overlay: o, lights: l)
    }()

    public static func theme(id: String) -> Theme? { all.first { $0.id == id } }

    // MARK: - The collection

    /// More looks, each pairing a typeface with a lyric style, colors, lights and an entrance and
    /// exit that suit its mood. Every theme has its own font: the eight Lyra Originals (matched to
    /// mood: metal, razor, stencil, techno, neon, gothic, soft and pixel) and tasteful system fonts.
    /// No gimmick system fonts are used here (see `FontCatalog.featured`).
    static let collection: [Theme] = [
        make("vinyl", "Vinyl", style: "scroll", font: "Didot-Bold", size: 50,
             highlight: RGBA(1, 0.92, 0.8), base: RGBA(1, 0.92, 0.8, 0.33), glowColor: RGBA(0.9, 0.35, 0.25), glow: 0.4,
             entrance: .slideLeft, exit: .fade, duration: 0.6,
             lights: light(intensity: 0.6, thickness: 24, primary: RGBA(1, 0.6, 0.2), secondary: RGBA(0.9, 0.25, 0.2))),
        make("poster", "Poster", style: "cinematic", font: "Impact", size: 60, tracking: 0.02, textCase: .upper,
             highlight: RGBA(1, 0.9, 0.15), base: RGBA(1, 1, 1, 0.3), glowColor: RGBA(1, 0.5, 0.1), glow: 0.6, shadow: 0.7,
             entrance: .zoomIn, exit: .shrink, duration: 0.3,
             lights: light(intensity: 1, thickness: 52, reactivity: 1, primary: RGBA(1, 0.85, 0.1), secondary: RGBA(1, 0.45, 0.1))),
        make("noir", "Noir", style: "karaoke", font: "Copperplate-Bold", size: 44, tracking: 0.12, textCase: .upper,
             highlight: RGBA(1, 1, 1), base: RGBA(0.8, 0.8, 0.8, 0.3), glowColor: RGBA(1, 1, 1), glow: 0, shadow: 0.7, nextLine: false,
             entrance: .fade, exit: .fade, duration: 0.9,
             lights: light(on: false)),
        make("sunset", "Sunset", style: "wave", font: "Optima-ExtraBlack", size: 50,
             highlight: RGBA(1, 0.92, 0.82), base: RGBA(1, 0.9, 0.8, 0.32), glowColor: RGBA(1, 0.45, 0.35), glow: 0.8,
             entrance: .drop, exit: .rise, duration: 0.5,
             lights: light(intensity: 0.85, thickness: 44, drift: 0.08, primary: RGBA(1, 0.55, 0.2), secondary: RGBA(0.95, 0.25, 0.6))),
        make("ocean", "Ocean", style: "scroll", font: "GillSans-Bold", size: 50,
             highlight: RGBA(0.85, 1, 1), base: RGBA(0.8, 0.95, 1, 0.32), glowColor: RGBA(0.2, 0.8, 1), glow: 0.7,
             entrance: .slideRight, exit: .fade, duration: 0.55,
             lights: light(intensity: 0.9, thickness: 40, primary: RGBA(0.1, 0.75, 0.95), secondary: RGBA(0.15, 0.4, 0.95))),
        make("forest", "Forest", style: "karaoke", font: "Palatino-Bold", size: 48,
             highlight: RGBA(0.9, 1, 0.85), base: RGBA(0.85, 1, 0.8, 0.32), glowColor: RGBA(0.4, 0.9, 0.4), glow: 0.5,
             entrance: .cascade, exit: .fade, duration: 0.5, stagger: 0.06,
             lights: light(intensity: 0.55, thickness: 22, idle: 0.3, drift: 0.03, primary: RGBA(0.3, 0.85, 0.4), secondary: RGBA(0.8, 0.9, 0.3))),
        make("retro-wave", "Retro Wave", style: "pop", font: "LyraRetro-Regular", size: 52, textCase: .upper,
             highlight: RGBA(1, 0.4, 0.9), base: RGBA(1, 0.7, 1, 0.28), glowColor: RGBA(0.2, 0.9, 1), glow: 1.1, shadow: 0.2,
             entrance: .glitch, exit: .blur, duration: 0.4,
             lights: light(intensity: 1, thickness: 46, reactivity: 1, drift: 0.1, primary: RGBA(1, 0.2, 0.8), secondary: RGBA(0.1, 0.9, 1))),
        make("blueprint", "Blueprint", style: "typewriter", font: "LyraCircuit-Regular", size: 46, tracking: 0.03, textCase: .upper,
             highlight: RGBA(0.75, 0.95, 1), base: RGBA(0.75, 0.95, 1, 0), glowColor: RGBA(0.3, 0.8, 1), glow: 0.5, shadow: 0.4,
             entrance: .fade, exit: .none, duration: 0.3,
             lights: light(on: false)),
        make("friendly", "Friendly", style: "karaoke", font: "LyraMonolineRound-Regular", size: 56,
             highlight: RGBA(0.75, 0.85, 1), base: RGBA(0.75, 0.85, 1, 0.33), glowColor: RGBA(0.4, 0.6, 1), glow: 0.5,
             entrance: .blur, exit: .fade, duration: 0.6,
             lights: light(intensity: 0.6, idle: 0.3, primary: RGBA(0.4, 0.6, 1), secondary: RGBA(0.7, 0.4, 1))),
        make("elegant", "Elegant", style: "cinematic", font: "BodoniSvtyTwoITCTT-Bold", size: 62,
             highlight: RGBA(1, 0.85, 0.5), base: RGBA(1, 0.88, 0.6, 0.32), glowColor: RGBA(1, 0.7, 0.2), glow: 0.6,
             entrance: .zoomOut, exit: .blur, duration: 0.7,
             lights: light(intensity: 0.5, thickness: 18, idle: 0.28, primary: RGBA(1, 0.8, 0.35), secondary: RGBA(1, 0.65, 0.25))),
        make("stamp", "Stamp", style: "pop", font: "LyraStencilOps-Regular", size: 52, tracking: 0.02, textCase: .upper,
             highlight: RGBA(0.95, 0.9, 0.55), base: RGBA(0.9, 0.9, 0.7, 0.3), glowColor: RGBA(0.9, 0.55, 0.15), glow: 0.5, shadow: 0.7,
             entrance: .spring, exit: .shrink, duration: 0.5,
             lights: light(intensity: 0.8, thickness: 36, reactivity: 1, primary: RGBA(0.85, 0.6, 0.2), secondary: RGBA(0.5, 0.65, 0.25))),
        make("newsprint", "Newsprint", style: "typewriter", font: "AmericanTypewriter-Bold", size: 44,
             highlight: RGBA(1, 1, 0.95), base: RGBA(1, 1, 0.95, 0), glowColor: RGBA(1, 1, 1), glow: 0, shadow: 0.8, anchorY: 0.2,
             entrance: .rise, exit: .fade, duration: 0.3,
             lights: light(on: false)),
        make("arcade", "Arcade", style: "pop", font: "LyraPixel-Regular", size: 46, textCase: .upper,
             highlight: RGBA(0.5, 1, 0.4), base: RGBA(0.6, 1, 0.5, 0.3), glowColor: RGBA(1, 0.9, 0.2), glow: 0.9,
             entrance: .slideRight, exit: .none, duration: 0.35,
             lights: light(intensity: 0.9, thickness: 34, reactivity: 1, primary: RGBA(0.4, 1, 0.3), secondary: RGBA(1, 0.9, 0.2))),
        make("midnight-jazz", "Midnight Jazz", style: "scroll", font: "HoeflerText-Black", size: 50,
             highlight: RGBA(1, 0.9, 0.7), base: RGBA(1, 0.9, 0.7, 0.3), glowColor: RGBA(0.3, 0.4, 1), glow: 0.6,
             entrance: .fade, exit: .fade, duration: 0.8,
             lights: light(intensity: 0.8, thickness: 36, reactivity: 0.6, drift: 0.04, primary: RGBA(0.25, 0.35, 0.95), secondary: RGBA(1, 0.8, 0.4))),
        make("desert", "Desert", style: "karaoke", font: "Rockwell-Bold", size: 48,
             highlight: RGBA(1, 0.9, 0.7), base: RGBA(1, 0.9, 0.7, 0.32), glowColor: RGBA(1, 0.55, 0.2), glow: 0.5,
             entrance: .rise, exit: .rise, duration: 0.5,
             lights: light(intensity: 0.7, thickness: 30, primary: RGBA(1, 0.6, 0.2), secondary: RGBA(0.95, 0.8, 0.5))),
        make("aurora", "Aurora", style: "wave", font: "AvenirNext-UltraLight", size: 56,
             highlight: RGBA(1, 1, 1), base: RGBA(1, 1, 1, 0.3), glowColor: RGBA(0.5, 1, 0.8), glow: 0.9, shadow: 0.3,
             entrance: .blur, exit: .blur, duration: 0.8,
             lights: light(intensity: 0.9, thickness: 52, drift: 0.15, artwork: true), artwork: true),
        make("studio", "Studio", style: "karaoke", font: "DINAlternate-Bold", size: 48,
             highlight: RGBA(1, 1, 1), base: RGBA(1, 1, 1, 0.34), glowColor: RGBA(1, 1, 1), glow: 0.2,
             entrance: .drop, exit: .fade, duration: 0.3,
             lights: light(intensity: 0.5, thickness: 14, idle: 0.15, primary: RGBA(0.95, 0.95, 1), secondary: RGBA(0.7, 0.8, 1))),
        make("marquee", "Marquee", style: "scroll", font: "Superclarendon-Black", size: 50,
             highlight: RGBA(1, 0.96, 0.85), base: RGBA(1, 0.96, 0.85, 0.32), glowColor: RGBA(1, 0.8, 0.3), glow: 0.7,
             entrance: .zoomIn, exit: .shrink, duration: 0.5,
             lights: light(intensity: 0.85, thickness: 30, primary: RGBA(1, 0.8, 0.3), secondary: RGBA(1, 0.5, 0.2))),
        make("dream-pop", "Dream Pop", style: "wave", font: "ArialRoundedMTBold", size: 50,
             highlight: RGBA(1, 0.9, 1), base: RGBA(1, 0.9, 1, 0.3), glowColor: RGBA(1, 0.6, 0.9), glow: 0.9,
             entrance: .spring, exit: .blur, duration: 0.6,
             lights: light(intensity: 0.8, thickness: 42, drift: 0.1, artwork: true), artwork: true),
        make("billboard", "Billboard", style: "focus", font: "DINCondensed-Bold", size: 62, tracking: 0.04, textCase: .upper,
             highlight: RGBA(1, 1, 1), base: RGBA(1, 1, 1, 0.3), glowColor: RGBA(1, 0.2, 0.2), glow: 0.5,
             entrance: .drop, exit: .rise, duration: 0.35,
             lights: light(intensity: 1, thickness: 38, reactivity: 1, primary: RGBA(1, 0.2, 0.2), secondary: RGBA(1, 0.5, 0.2))),
        make("forge", "Forge", style: "karaoke", font: "LyraForge-Regular", size: 52, tracking: 0.02, textCase: .upper,
             highlight: RGBA(1, 0.88, 0.7), base: RGBA(1, 0.7, 0.5, 0.3), glowColor: RGBA(1, 0.3, 0.1), glow: 0.9, shadow: 0.8,
             entrance: .drop, exit: .shrink, duration: 0.35,
             lights: light(intensity: 1, thickness: 44, reactivity: 1, idle: 0.2, drift: 0.04, primary: RGBA(1, 0.25, 0.08), secondary: RGBA(1, 0.65, 0.1))),
        make("thorn", "Thorn", style: "wave", font: "LyraThorn-Regular", size: 58, tracking: 0.03, textCase: .upper,
             highlight: RGBA(0.92, 0.88, 1), base: RGBA(0.85, 0.8, 1, 0.3), glowColor: RGBA(0.6, 0.4, 1), glow: 0.7, shadow: 0.5,
             entrance: .fade, exit: .blur, duration: 0.9,
             lights: light(intensity: 0.6, thickness: 26, idle: 0.2, drift: 0.03, primary: RGBA(0.55, 0.35, 1), secondary: RGBA(0.9, 0.9, 1))),
        make("library", "Library", style: "scroll", font: "Cochin-Bold", size: 50,
             highlight: RGBA(1, 0.93, 0.78), base: RGBA(1, 0.93, 0.78, 0.3), glowColor: RGBA(0.9, 0.7, 0.35), glow: 0.3, shadow: 0.6,
             entrance: .rise, exit: .fade, duration: 0.7,
             lights: light(on: false)),
        make("editorial", "Editorial", style: "karaoke", font: "Charter-Black", size: 48,
             highlight: RGBA(1, 1, 1), base: RGBA(1, 1, 1, 0.3), glowColor: RGBA(1, 1, 1), glow: 0.1, shadow: 0.6,
             entrance: .fade, exit: .fade, duration: 0.5,
             lights: light(intensity: 0.4, thickness: 12, idle: 0.2, primary: RGBA(1, 1, 1), secondary: RGBA(0.8, 0.8, 0.85))),
        make("console", "Console", style: "typewriter", font: "Monaco", size: 40,
             highlight: RGBA(1, 0.78, 0.25), base: RGBA(1, 0.78, 0.25, 0), glowColor: RGBA(1, 0.6, 0.1), glow: 0.6, shadow: 0.4, anchorY: 0.2,
             entrance: .none, exit: .none, duration: 0.3,
             lights: light(on: false)),
        make("ledger", "Ledger", style: "karaoke", font: "CourierNewPS-BoldMT", size: 42,
             highlight: RGBA(1, 0.98, 0.9), base: RGBA(1, 0.98, 0.9, 0.3), glowColor: RGBA(1, 0.95, 0.8), glow: 0.1, shadow: 0.7,
             entrance: .fade, exit: .none, duration: 0.4,
             lights: light(on: false)),
        make("big-top", "Big Top", style: "pop", font: "BigCaslon-Medium", size: 56,
             highlight: RGBA(1, 0.95, 0.75), base: RGBA(1, 0.9, 0.7, 0.3), glowColor: RGBA(1, 0.25, 0.2), glow: 0.7, shadow: 0.6,
             entrance: .zoomOut, exit: .shrink, duration: 0.5,
             lights: light(intensity: 0.9, thickness: 40, reactivity: 0.9, primary: RGBA(1, 0.25, 0.2), secondary: RGBA(1, 0.85, 0.3))),
        make("compact", "Compact", style: "focus", font: "HelveticaNeue-CondensedBlack", size: 66, tracking: 0.02, textCase: .upper,
             highlight: RGBA(1, 1, 1), base: RGBA(1, 1, 1, 0.28), glowColor: RGBA(0.3, 1, 0.8), glow: 0.4, shadow: 0.6,
             entrance: .drop, exit: .none, duration: 0.3,
             lights: light(intensity: 0.7, thickness: 28, reactivity: 0.9, primary: RGBA(0.3, 1, 0.8), secondary: RGBA(0.2, 0.6, 1))),
        make("skyline", "Skyline", style: "karaoke", font: "Futura-CondensedExtraBold", size: 60, tracking: 0.05, textCase: .upper,
             highlight: RGBA(0.9, 0.95, 1), base: RGBA(0.85, 0.9, 1, 0.3), glowColor: RGBA(0.4, 0.5, 1), glow: 0.7,
             entrance: .slideLeft, exit: .fade, duration: 0.45,
             lights: light(intensity: 0.9, thickness: 46, drift: 0.07, primary: RGBA(0.35, 0.45, 1), secondary: RGBA(0.75, 0.35, 1))),

        // The hand-drawn set (see `FontCatalog.handDrawn`): real lowercase and organic shapes.
        make("punk", "Punk Rock", style: "pop", font: "LyraBrush-Regular", size: 60,
             highlight: RGBA(1, 0.95, 0.25), base: RGBA(1, 1, 1, 0.3), glowColor: RGBA(1, 0.15, 0.25), glow: 0.7, shadow: 0.7,
             entrance: .glitch, exit: .shrink, duration: 0.35,
             lights: light(intensity: 1, thickness: 44, reactivity: 1, idle: 0.15, primary: RGBA(1, 0.15, 0.25), secondary: RGBA(1, 0.9, 0.2))),
        make("street", "Street", style: "wave", font: "LyraTag-Regular", size: 58,
             highlight: RGBA(1, 1, 1), base: RGBA(1, 1, 1, 0.3), glowColor: RGBA(1, 0.2, 0.75), glow: 0.8, shadow: 0.6,
             entrance: .spring, exit: .rise, duration: 0.5,
             lights: light(intensity: 0.95, thickness: 40, reactivity: 1, drift: 0.09, primary: RGBA(1, 0.2, 0.75), secondary: RGBA(0.1, 0.9, 1))),
        make("cathedral", "Cathedral", style: "cinematic", font: "LyraGothic-Regular", size: 66,
             highlight: RGBA(0.98, 0.93, 0.85), base: RGBA(0.95, 0.88, 0.8, 0.3), glowColor: RGBA(0.85, 0.1, 0.1), glow: 0.7, shadow: 0.7,
             entrance: .blur, exit: .blur, duration: 0.7,
             lights: light(intensity: 0.6, thickness: 34, reactivity: 0.7, idle: 0.2, drift: 0.03, primary: RGBA(0.85, 0.1, 0.1), secondary: RGBA(0.4, 0.05, 0.1))),
        make("diary", "Diary", style: "karaoke", font: "LyraHand-Regular", size: 58,
             highlight: RGBA(1, 0.96, 0.85), base: RGBA(1, 0.95, 0.85, 0.34), glowColor: RGBA(1, 0.85, 0.55), glow: 0.35, shadow: 0.6,
             entrance: .cascade, exit: .fade, duration: 0.55, stagger: 0.07,
             lights: light(intensity: 0.45, thickness: 22, idle: 0.28, drift: 0.03, primary: RGBA(1, 0.85, 0.55), secondary: RGBA(1, 0.7, 0.6))),
        make("frontier", "Frontier", style: "scroll", font: "LyraSaloon-Regular", size: 60,
             highlight: RGBA(1, 0.92, 0.72), base: RGBA(1, 0.9, 0.7, 0.32), glowColor: RGBA(0.95, 0.55, 0.15), glow: 0.5, shadow: 0.7,
             entrance: .rise, exit: .rise, duration: 0.5,
             lights: light(intensity: 0.7, thickness: 28, primary: RGBA(0.95, 0.6, 0.2), secondary: RGBA(0.7, 0.35, 0.15))),
        make("candy", "Candy", style: "pop", font: "LyraBubble-Regular", size: 56,
             highlight: RGBA(1, 0.95, 1), base: RGBA(1, 0.85, 0.95, 0.4), glowColor: RGBA(1, 0.45, 0.8), glow: 0.9, shadow: 0.35,
             entrance: .spring, exit: .shrink, duration: 0.55,
             lights: light(intensity: 0.85, thickness: 42, reactivity: 0.9, drift: 0.1, artwork: true), artwork: true),
        make("katana", "Katana", style: "cinematic", font: "LyraBladeDrawn-Regular", size: 62, textCase: .upper,
             highlight: RGBA(0.95, 0.96, 1), base: RGBA(0.85, 0.88, 0.95, 0.3), glowColor: RGBA(1, 0.2, 0.25), glow: 0.6, shadow: 0.6,
             entrance: .slideLeft, exit: .fade, duration: 0.3,
             lights: light(intensity: 0.8, thickness: 30, reactivity: 1, idle: 0.12, primary: RGBA(1, 0.2, 0.25), secondary: RGBA(0.9, 0.92, 1))),
        make("razor", "Razor", style: "wave", font: "LyraBlade-Regular", size: 58, textCase: .upper,
             highlight: RGBA(0.9, 0.97, 1), base: RGBA(0.8, 0.92, 1, 0.3), glowColor: RGBA(0.35, 0.85, 1), glow: 0.7, shadow: 0.5,
             entrance: .slideRight, exit: .fade, duration: 0.3,
             lights: light(intensity: 0.85, thickness: 30, reactivity: 1, idle: 0.15, drift: 0.08, primary: RGBA(0.35, 0.85, 1), secondary: RGBA(0.85, 0.95, 1))),
        make("foundry", "Foundry", style: "karaoke", font: "LyraForgeDrawn-Regular", size: 54, textCase: .upper,
             highlight: RGBA(1, 0.9, 0.72), base: RGBA(1, 0.72, 0.5, 0.3), glowColor: RGBA(1, 0.4, 0.1), glow: 0.8, shadow: 0.8,
             entrance: .drop, exit: .shrink, duration: 0.35,
             lights: light(intensity: 0.95, thickness: 42, reactivity: 1, idle: 0.2, primary: RGBA(1, 0.4, 0.1), secondary: RGBA(1, 0.75, 0.2))),
        make("night-drive", "Night Drive", style: "focus", font: "LyraNeonDrawn-Regular", size: 62,
             highlight: RGBA(0.9, 1, 1), base: RGBA(0.8, 0.95, 1, 0.3), glowColor: RGBA(0.1, 0.9, 1), glow: 1.0, shadow: 0.3,
             entrance: .blur, exit: .blur, duration: 0.6,
             lights: light(intensity: 1, thickness: 50, reactivity: 0.9, drift: 0.12, primary: RGBA(0.1, 0.9, 1), secondary: RGBA(0.9, 0.2, 1))),
        make("cabinet", "Cabinet", style: "typewriter", font: "LyraPixelDrawn-Regular", size: 46,
             highlight: RGBA(1, 0.78, 0.25), base: RGBA(1, 0.78, 0.25, 0), glowColor: RGBA(1, 0.55, 0.1), glow: 0.7, shadow: 0.5, anchorY: 0.2,
             entrance: .none, exit: .none, duration: 0.3,
             lights: light(on: false)),
        make("depot", "Depot", style: "focus", font: "LyraStencilDrawn-Regular", size: 64, textCase: .upper,
             highlight: RGBA(0.92, 0.95, 0.8), base: RGBA(0.85, 0.9, 0.7, 0.3), glowColor: RGBA(0.95, 0.6, 0.15), glow: 0.4, shadow: 0.8,
             entrance: .zoomIn, exit: .shrink, duration: 0.35,
             lights: light(intensity: 0.7, thickness: 30, reactivity: 0.8, primary: RGBA(0.95, 0.6, 0.15), secondary: RGBA(0.5, 0.6, 0.25))),

        // Later additions from the drawn set. Add a theme here for each new font in `Fonts/`; the
        // "every Lyra font is the face of exactly one theme" test fails until you do.
        make("serenade", "Serenade", style: "focus", font: "LyraScript-Regular", size: 68,
             highlight: RGBA(1, 0.93, 0.92), base: RGBA(1, 0.85, 0.88, 0.34), glowColor: RGBA(1, 0.55, 0.65), glow: 0.55, shadow: 0.45,
             entrance: .blur, exit: .fade, duration: 0.8,
             lights: light(intensity: 0.6, thickness: 36, reactivity: 0.55, idle: 0.28, drift: 0.04, primary: RGBA(1, 0.5, 0.62), secondary: RGBA(0.95, 0.75, 0.6))),
        make("black-rose", "Black Rose", style: "cinematic", font: "LyraThornDrawn-Regular", size: 60, tracking: 0.02,
             highlight: RGBA(0.97, 0.9, 0.92), base: RGBA(0.8, 0.6, 0.65, 0.3), glowColor: RGBA(0.75, 0.05, 0.25), glow: 0.75, shadow: 0.8,
             entrance: .rise, exit: .blur, duration: 0.75,
             lights: light(intensity: 0.55, thickness: 30, reactivity: 0.6, idle: 0.2, drift: 0.03, primary: RGBA(0.75, 0.05, 0.25), secondary: RGBA(0.3, 0.02, 0.15))),
        make("mainframe", "Mainframe", style: "typewriter", font: "LyraCircuitDrawn-Regular", size: 48, tracking: 0.03, textCase: .upper,
             highlight: RGBA(0.55, 1, 0.8), base: RGBA(0.4, 0.9, 0.7, 0.28), glowColor: RGBA(0.1, 1, 0.6), glow: 0.85, shadow: 0.3, anchorY: 0.22,
             entrance: .glitch, exit: .fade, duration: 0.3,
             lights: light(intensity: 0.8, thickness: 24, reactivity: 1, idle: 0.15, drift: 0.1, primary: RGBA(0.1, 1, 0.6), secondary: RGBA(0.1, 0.6, 1))),
    ]

    private static func light(on: Bool = true, intensity: Float = 0.85, thickness: Double = 28, reactivity: Float = 0.8,
                              idle: Float = 0.22, drift: Double = 0.05, primary: RGBA? = nil, secondary: RGBA? = nil,
                              artwork: Bool = false) -> LightConfig {
        var l = LightConfig()
        l.enabled = on
        l.intensity = intensity
        l.thickness = thickness
        l.beatReactivity = reactivity
        l.idleGlow = idle
        l.driftSpeed = drift
        l.primary = primary
        l.secondary = secondary
        // Manual colors turn album-following off for the lights; otherwise follow the cover.
        l.useArtworkColors = artwork || (primary == nil && secondary == nil)
        return l
    }

    private static func make(_ slug: String, _ name: String, style: String, font: String, size: Double,
                             tracking: Double = 0, italic: Bool = false, textCase: TextCase = .asWritten,
                             highlight: RGBA, base: RGBA, glowColor: RGBA, glow: Float, shadow: Float = 0.5,
                             nextLine: Bool = true, anchorY: Double = 0.16,
                             entrance: EntranceAnimation, exit: ExitAnimation, duration: Double = 0.45, stagger: Double = 0.05,
                             lights: LightConfig, artwork: Bool = false) -> Theme {
        var o = OverlayConfig()
        o.font = FontSpec(family: font, size: size, weight: 0, tracking: tracking, italic: italic)
        o.textCase = textCase
        o.highlightColor = highlight
        o.baseColor = base
        o.glowColor = glowColor
        o.glow = glow
        o.shadow = shadow
        o.showNextLine = nextLine
        o.anchorY = anchorY
        o.entrance = entrance
        o.exit = exit
        o.entranceDuration = duration
        o.entranceStagger = stagger
        return Theme(id: "builtin.\(slug)", name: name, styleID: style, overlay: o, lights: lights, useArtworkColors: artwork)
    }
}
