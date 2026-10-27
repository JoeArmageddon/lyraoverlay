import Foundation

/// Eases a palette toward each new target so the border's colors glide when the background
/// changes (or a video moves to a new scene) instead of snapping. Pure and deterministic.
public struct PaletteSmoother: Sendable {
    /// Seconds for the colors to close about 63% of the gap to the target.
    public var timeConstant: Double
    private var current: Palette?

    public init(timeConstant: Double = 0.8) {
        self.timeConstant = timeConstant
    }

    /// The first call returns `target` as is. After that each color moves toward the target by
    /// `1 - e^(-dt / timeConstant)` of the remaining distance: it approaches without overshooting,
    /// and the result does not depend on how `dt` is split across frames.
    public mutating func update(target: Palette, dt: Double) -> Palette {
        guard let from = current else {
            current = target
            return target
        }
        let k = Float(timeConstant > 0 ? 1 - exp(-max(dt, 0) / timeConstant) : 1)
        func ease(_ a: RGBA, _ b: RGBA) -> RGBA {
            RGBA(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
        }
        let next = Palette(
            dominant: ease(from.dominant, target.dominant),
            accent: ease(from.accent, target.accent),
            secondary: ease(from.secondary, target.secondary),
            swatches: target.swatches,
            isDark: target.isDark)
        current = next
        return next
    }

    /// Forget the current colors; the next update starts at its target.
    public mutating func reset() { current = nil }
}
