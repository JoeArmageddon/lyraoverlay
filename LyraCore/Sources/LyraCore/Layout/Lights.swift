import Foundation

public struct LightConfig: Equatable, Codable, Sendable {
    public var enabled = true
    /// Falloff distance of the glow, in points.
    public var thickness = 28.0
    /// 0...1 overall brightness.
    public var intensity: Float = 0.85
    /// Matches the display's corner radius so the glow hugs the screen shape.
    public var cornerRadius = 14.0
    /// 0 ignores the music, 1 pulses fully on every beat.
    public var beatReactivity: Float = 0.8
    /// Brightness between beats and when nothing is playing.
    public var idleGlow: Float = 0.22
    /// Gradient rotation around the screen, in turns per second.
    public var driftSpeed = 0.05
    /// Follow the album art palette when there is one.
    public var useArtworkColors = true
    /// Manual colors, used when artwork colors are off or unavailable.
    public var primary: RGBA?
    public var secondary: RGBA?

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.get(.enabled, enabled)
        thickness = c.get(.thickness, thickness)
        intensity = c.get(.intensity, intensity)
        cornerRadius = c.get(.cornerRadius, cornerRadius)
        beatReactivity = c.get(.beatReactivity, beatReactivity)
        idleGlow = c.get(.idleGlow, idleGlow)
        driftSpeed = c.get(.driftSpeed, driftSpeed)
        useArtworkColors = c.get(.useArtworkColors, useArtworkColors)
        primary = (try? c.decodeIfPresent(RGBA.self, forKey: .primary)) ?? nil
        secondary = (try? c.decodeIfPresent(RGBA.self, forKey: .secondary)) ?? nil
    }
}

/// What the renderer needs to draw one frame of edge lighting.
public struct LightParams: Equatable, Sendable {
    public var primary: RGBA
    public var secondary: RGBA
    /// Falloff distance in points.
    public var thickness: Double
    public var cornerRadius: Double
    /// 0...1, already combining the idle glow and the music.
    public var intensity: Float
    /// Gradient rotation offset in turns (wraps at 1).
    public var phase: Double

    public init(primary: RGBA, secondary: RGBA, thickness: Double, cornerRadius: Double, intensity: Float, phase: Double) {
        self.primary = primary
        self.secondary = secondary
        self.thickness = thickness
        self.cornerRadius = cornerRadius
        self.intensity = intensity
        self.phase = phase
    }
}

public struct LightInput: Sendable {
    /// nil when audio capture isn't running (no permission, or stopped).
    public var features: AudioFeatures?
    public var primary: RGBA
    public var secondary: RGBA
    /// Seconds on any steady clock, used for drift and breathing.
    public var time: Double

    public init(features: AudioFeatures?, primary: RGBA, secondary: RGBA, time: Double) {
        self.features = features
        self.primary = primary
        self.secondary = secondary
        self.time = time
    }
}

public protocol LightEffect: Sendable {
    var name: String { get }
    /// nil means draw no lighting this frame.
    func params(_ input: LightInput, config: LightConfig) -> LightParams?
}

/// A glow along the screen edge: brighter and thicker on beats, with a slowly rotating gradient.
public struct RimGlowEffect: LightEffect {
    public let name = "Rim Glow"

    /// Colors used when neither the artwork nor the config supplies any.
    public static let defaultPrimary = RGBA(0.45, 0.65, 1.0)
    public static let defaultSecondary = RGBA(0.85, 0.45, 1.0)

    public init() {}

    public func params(_ input: LightInput, config: LightConfig) -> LightParams? {
        guard config.enabled else { return nil }

        let raw: Float
        var thickness = config.thickness
        if let f = input.features {
            let r = config.beatReactivity
            let body = (f.level * 0.25 + f.bass * 0.2) * r
            raw = config.idleGlow + body + f.beat * r * 0.55
            thickness *= 1 + Double(0.4 * f.beat * r + 0.2 * f.bass * r)
        } else {
            // No audio: a slow breathing glow so the lights still feel alive.
            let breath = 0.5 + 0.5 * sin(2 * Double.pi * input.time / 5)
            raw = config.idleGlow + 0.18 * Float(breath)
        }

        return LightParams(
            primary: config.primary ?? input.primary,
            secondary: config.secondary ?? input.secondary,
            thickness: thickness,
            cornerRadius: config.cornerRadius,
            intensity: min(1, max(0, raw * config.intensity)),
            phase: (input.time * config.driftSpeed).truncatingRemainder(dividingBy: 1))
    }
}

extension KeyedDecodingContainer {
    /// Decodes a key, falling back to `fallback` when it is missing or malformed, so a
    /// settings file written by an older version (or edited by hand) still loads.
    public func get<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}
