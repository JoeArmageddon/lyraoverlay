import Foundation
import CoreGraphics

/// Entrance and exit animations, applied on top of whatever a style laid out.
///
/// Pure and stateless: every value is derived from the frame's position and the line's own
/// timing, so the same input always gives the same output. Only items of the current line are
/// touched (`DrawItem.lineIndex`), never the next-line preview or neighbouring lines.
///
/// `.fade` and `.none` add nothing here. Every style already bakes a quick fade-in and a
/// linger-then-fade-out, which is what `.fade` means; `LyricsPipeline` removes those baked
/// fades for `.none`.
public enum Animator {
    public static func apply(_ items: [DrawItem], frame: LyricsFrame, config: OverlayConfig) -> [DrawItem] {
        let entranceActive = config.entrance != .none && config.entrance != .fade
        let exitActive = config.exit != .none && config.exit != .fade
        guard entranceActive || exitActive,
              let current = frame.cursor.lineIndex, frame.lines.indices.contains(current) else { return items }

        let line = frame.lines[current]
        // Scaling kinds scale the whole line about its own center, so words move together.
        let anchor = center(of: items, lineIndex: current)

        return items.map { item in
            guard item.lineIndex == current else { return item }
            var out = item
            if entranceActive { out = entrance(out, line: line, frame: frame, config: config, anchor: anchor) }
            if exitActive { out = leave(out, line: line, frame: frame, config: config, anchor: anchor) }
            return out
        }
    }

    // MARK: - Entrance

    private static func entrance(_ item: DrawItem, line: LyricLine, frame: LyricsFrame, config: OverlayConfig,
                                 anchor: CGPoint) -> DrawItem {
        // A zero duration means the line simply appears.
        guard config.entranceDuration > 0 else { return item }
        let duration = config.entranceDuration
        var age = frame.position - line.start
        if config.entrance == .cascade { age -= Double(item.wordIndex) * max(0, config.entranceStagger) }
        let t = clamp(age / duration)
        guard t < 1 else { return item }   // finished: exactly the style's own layout

        var out = item
        let h = Double(max(item.size.height, 1))
        let e = easeOut(t)

        switch config.entrance {
        case .none, .fade:
            break
        case .rise:
            out.center.y += CGFloat(0.5 * h * (1 - e))
            out.opacity *= Float(ramp(t, over: 0.6))
        case .drop:
            out.center.y -= CGFloat(0.5 * h * (1 - e))
            out.opacity *= Float(ramp(t, over: 0.6))
        case .slideLeft:
            out.center.x -= CGFloat(1.5 * h * (1 - e))
            out.opacity *= Float(ramp(t, over: 0.5))
        case .slideRight:
            out.center.x += CGFloat(1.5 * h * (1 - e))
            out.opacity *= Float(ramp(t, over: 0.5))
        case .zoomIn:
            out = scaled(out, by: lerp(0.6, 1, e), about: anchor)
            out.opacity *= Float(ramp(t, over: 0.5))
        case .zoomOut:
            out = scaled(out, by: lerp(1.6, 1, e), about: anchor)
            out.opacity *= Float(ramp(t, over: 0.5))
        case .spring:
            out = scaled(out, by: springScale(t), about: anchor)
            out.opacity *= Float(ramp(t, over: 0.2))
        case .blur:
            out = scaled(out, by: lerp(1.06, 1, e), about: anchor)
            out.blur = max(out.blur, Float(1 - e))
            out.opacity *= Float(ramp(t, over: 0.6))
        case .cascade:
            out.center.y += CGFloat(0.6 * h * (1 - e))
            out.opacity *= Float(ramp(t, over: 0.7))
        case .glitch:
            out = glitch(out, age: age, t: t, h: h)
        }
        return out
    }

    /// A damped spring from 0.5 that overshoots to about 1.12 and settles at exactly 1.
    private static func springScale(_ t: Double) -> Double {
        // The taper brings the oscillation to exactly zero at t = 1 so there is no jump at the end.
        let taper = 1 - smooth((t - 0.75) / 0.25)
        let g = exp(-3.2 * t) * cos(2 * Double.pi * 1.15 * t) * taper
        return 1 - 0.5 * g
    }

    /// Horizontal jitter and flicker for the first third of the entrance, then nothing.
    private static func glitch(_ item: DrawItem, age: Double, t: Double, h: Double) -> DrawItem {
        let burst = 0.35
        guard t < burst else { return item }
        let u = t / burst
        // Jitter steps every ~45 ms, deterministic per step and word.
        let step = Int((max(0, age) / 0.045).rounded(.down))
        let side: Double = hash(step, item.wordIndex, 1) < 0.5 ? -1 : 1
        let magnitude = 0.3 + 0.7 * hash(step, item.wordIndex, 2)
        var out = item
        out.center.x += CGFloat(side * magnitude * 0.45 * h * (1 - u))
        if u < 0.8, hash(step, item.wordIndex, 3) < 0.35 { out.opacity *= 0.25 }
        return out
    }

    // MARK: - Exit

    private static func leave(_ item: DrawItem, line: LyricLine, frame: LyricsFrame, config: OverlayConfig,
                              anchor: CGPoint) -> DrawItem {
        // With no fade-out the line never leaves on its own (it stays until the next one replaces it),
        // so there is nothing to animate; displacing it forever would be wrong.
        guard config.fadeOutDuration > 0 else { return item }
        let start = line.sungEnd + config.lingerAfterSung
        let t = clamp((frame.position - start) / config.fadeOutDuration)
        guard t > 0 else { return item }   // not leaving yet

        var out = item
        let h = Double(max(item.size.height, 1))
        switch config.exit {
        case .none, .fade:
            break
        case .rise:
            out.center.y -= CGFloat(0.6 * h * t * t)
        case .shrink:
            out = scaled(out, by: lerp(1, 0.85, easeOut(t)), about: anchor)
        case .blur:
            out.blur = max(out.blur, Float(t))
        }
        return out
    }

    // MARK: - Helpers

    /// Scales the item about `anchor`: its own size and its distance from the anchor.
    private static func scaled(_ item: DrawItem, by k: Double, about anchor: CGPoint) -> DrawItem {
        var out = item
        out.center = CGPoint(x: anchor.x + (item.center.x - anchor.x) * CGFloat(k),
                             y: anchor.y + (item.center.y - anchor.y) * CGFloat(k))
        out.scale = item.scale * Float(k)
        return out
    }

    /// Middle of the bounding box of the current line's item centers.
    private static func center(of items: [DrawItem], lineIndex: Int) -> CGPoint {
        let mine = items.filter { $0.lineIndex == lineIndex }
        guard let first = mine.first else { return .zero }
        var minX = first.center.x, maxX = first.center.x, minY = first.center.y, maxY = first.center.y
        for item in mine {
            minX = min(minX, item.center.x); maxX = max(maxX, item.center.x)
            minY = min(minY, item.center.y); maxY = max(maxY, item.center.y)
        }
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    private static func smooth(_ t: Double) -> Double { let x = clamp(t); return x * x * (3 - 2 * x) }
    /// Opacity that reaches 1 once `t` passes `over` (a fraction of the entrance).
    private static func ramp(_ t: Double, over: Double) -> Double { smooth(t / over) }

    /// Deterministic value in 0..<1 from three integers (an integer hash, not a random generator).
    private static func hash(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var x = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791))
        x ^= x >> 33
        x = x &* 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x = x &* 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }
}
