import Foundation

public enum CapStyle {
    case butt
    case round
    /// A triangular spike beyond the end, as wide as the stroke.
    case spike(Double)
    /// The last stretch narrows to a point (the tip stays on the end of the line).
    case taper(Double)
    /// A square pad, like a pad on a circuit trace.
    case pad(Double)
}

public enum JoinStyle {
    case miter(Double)
    case round
    case bevel
}

public enum DotStyle {
    case circle, square, diamond, spike
}

/// Saw-tooth serrations along the outer edge of long strokes.
public struct Teeth {
    public var pitch: Double
    public var width: Double
    public var height: Double
    public var margin: Double
    public var minLength: Double
    /// 0...1: how much the tooth heights vary (deterministically) so the edge looks hand-cut.
    public var variation: Double
    public init(pitch: Double, width: Double, height: Double, margin: Double, minLength: Double, variation: Double) {
        self.pitch = pitch; self.width = width; self.height = height
        self.margin = margin; self.minLength = minLength; self.variation = variation
    }
}

/// A deterministic hash in 0...1, so serrations and thorns are the same on every run.
func hash01(_ a: Int, _ b: Int, _ c: Int = 0) -> Double {
    var h = UInt64(truncatingIfNeeded: a) &* 0x9E3779B97F4A7C15
    h ^= UInt64(truncatingIfNeeded: b) &+ 0x7F4A7C15 &+ (h << 6) &+ (h >> 2)
    h ^= UInt64(truncatingIfNeeded: c) &* 0xBF58476D1CE4E5B9
    h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
    h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
    h ^= h >> 31
    return Double(h % 10_000) / 10_000
}

/// Turns centerline polylines into filled outline pieces for one style.
struct Stroker {
    var hw: Double
    var cap: CapStyle
    var join: JoinStyle
    var dot: DotStyle
    var teeth: Teeth?
    var cornerThorn: Double?
    var roundSides = 14

    /// `center` is the middle of the glyph, used to decide which side of a stroke is "outside".
    func pieces(for pts: [Pt], closed: Bool, center: Pt, seed: Int) -> [Contour] {
        var out: [Contour] = []
        let n = pts.count
        guard n >= 2 else { return out }
        let segCount = closed ? n : n - 1

        for i in 0..<segCount {
            let a = pts[i], b = pts[(i + 1) % n]
            let length = (b - a).length
            guard length > 0.5 else { continue }
            let d = (b - a).unit
            var start = a, end = b
            var extA = 0.0, extB = 0.0

            if !closed {
                if i == 0 { applyCap(at: a, direction: d * -1, isStart: true, segLength: length, start: &start, end: &end, ext: &extA, out: &out) }
                if i == segCount - 1 { applyCap(at: b, direction: d, isStart: false, segLength: length, start: &start, end: &end, ext: &extB, out: &out) }
            }
            if let q = Geo.quad(start, end, hw: hw, extendA: extA, extendB: extB) { out.append(q) }
            if let t = teeth { out += serrations(from: a, to: b, teeth: t, center: center, seed: seed &+ i * 31) }
        }

        // Joins at the interior vertices (and all of them when closed).
        for i in 0..<n {
            if !closed && (i == 0 || i == n - 1) { continue }
            let prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            guard (cur - prev).length > 0.5, (next - cur).length > 0.5 else { continue }
            switch join {
            case .miter(let limit):
                if let w = Geo.joinWedge(prev: prev, cur: cur, next: next, hw: hw, miterLimit: limit) { out.append(w) }
            case .bevel:
                if let w = Geo.joinWedge(prev: prev, cur: cur, next: next, hw: hw, miterLimit: 0) { out.append(w) }
            case .round:
                if let c = Geo.regular(center: cur, radius: hw, sides: roundSides) { out.append(c) }
            }
            if let len = cornerThorn, let t = thorn(prev: prev, cur: cur, next: next, length: len) { out.append(t) }
        }
        return out
    }

    // MARK: - Caps

    private func applyCap(at p: Pt, direction: Pt, isStart: Bool, segLength: Double,
                          start: inout Pt, end: inout Pt, ext: inout Double, out: inout [Contour]) {
        // `direction` points away from the stroke, out through the end.
        let n = direction.normal * hw
        switch cap {
        case .butt: break
        case .round:
            if let c = Geo.regular(center: p, radius: hw, sides: roundSides) { out.append(c) }
        case .spike(let len):
            if let t = Geo.piece([p + n, p + direction * len, p - n]) { out.append(t) }
        case .taper(let len):
            let l = min(len, 0.42 * segLength)
            let cut = p - direction * l
            if isStart { start = cut } else { end = cut }
            if let t = Geo.piece([cut + n, p, cut - n]) { out.append(t) }
        case .pad(let size):
            if let s = Geo.regular(center: p, radius: size / 2 * 1.4142, sides: 4, rotation: .pi / 4) { out.append(s) }
        }
    }

    // MARK: - Serrations and thorns

    private func serrations(from a: Pt, to b: Pt, teeth t: Teeth, center: Pt, seed: Int) -> [Contour] {
        let length = (b - a).length
        guard length >= t.minLength else { return [] }
        let d = (b - a).unit
        let mid = (a + b) * 0.5
        let n = d.normal
        let outward = n.dot(mid - center)
        // Only strokes that sit toward the outside of the letter get teeth: interior bars would
        // fill the counters.
        guard abs(outward) > 60 else { return [] }
        let side: Double = outward > 0 ? 1 : -1
        var out: [Contour] = []
        let usable = length - 2 * t.margin
        guard usable >= t.width else { return [] }
        let count = max(1, Int(usable / t.pitch))
        let used = Double(count - 1) * t.pitch + t.width
        let first = t.margin + (usable - used) / 2
        for k in 0..<count {
            let s = first + Double(k) * t.pitch
            let h = t.height * (1 - t.variation * hash01(seed, k, 7))
            let base = n * (side * (hw - 4))
            let p0 = a + d * s + base
            let p1 = a + d * (s + t.width) + base
            // Ratchet teeth: the tip sits above the far end of the base.
            let tip = p1 + n * (side * (h + 4)) + d * (t.width * 0.12)
            if let tri = Geo.piece([p0, tip, p1]) { out.append(tri) }
        }
        return out
    }

    private func thorn(prev: Pt, cur: Pt, next: Pt, length: Double) -> Contour? {
        let d1 = (cur - prev).unit, d2 = (next - cur).unit
        let turn = d1.cross(d2)
        // Sharp bends only: a thorn on a gentle curve would just be a bump.
        guard abs(turn) > 0.8 else { return nil }
        let side: Double = turn > 0 ? -1 : 1
        let o1 = d1.normal * (hw * side), o2 = d2.normal * (hw * side)
        let outward = (o1 + o2).unit
        return Geo.piece([cur + o1, cur + outward * (hw * 1.4 + length), cur + o2])
    }

    // MARK: - Dots

    func dotPieces(at p: Pt) -> [Contour] {
        switch dot {
        case .circle: return [Geo.regular(center: p, radius: hw * 1.12, sides: 16)].compactMap { $0 }
        case .square:
            let h = hw * 1.05
            return [Geo.piece([Pt(p.x - h, p.y - h), Pt(p.x - h, p.y + h), Pt(p.x + h, p.y + h), Pt(p.x + h, p.y - h)])].compactMap { $0 }
        case .diamond: return [Geo.regular(center: p, radius: hw * 1.35, sides: 4)].compactMap { $0 }
        case .spike:
            let w = hw * 1.15
            return [Geo.piece([Pt(p.x - w, p.y - hw), Pt(p.x, p.y + hw * 2.1), Pt(p.x + w, p.y - hw)])].compactMap { $0 }
        }
    }
}

// MARK: - Stencil cuts

enum Clipper {
    /// Removes the parts of a polyline that lie inside `rects`, returning the pieces that remain.
    static func cut(_ pts: [Pt], closed: Bool, rects: [(minX: Double, minY: Double, maxX: Double, maxY: Double)]) -> [[Pt]] {
        guard !rects.isEmpty, pts.count >= 2 else { return [pts] }
        var segments: [(Pt, Pt)] = []
        let n = pts.count
        for i in 0..<(closed ? n : n - 1) { segments.append((pts[i], pts[(i + 1) % n])) }

        for r in rects {
            var next: [(Pt, Pt)] = []
            for (a, b) in segments {
                guard let (t0, t1) = clip(a, b, r) else { next.append((a, b)); continue }
                let d = b - a
                if t0 > 1e-6 { next.append((a, a + d * t0)) }
                if t1 < 1 - 1e-6 { next.append((a + d * t1, b)) }
            }
            segments = next
        }

        // Rejoin consecutive segments that still share an endpoint.
        var polylines: [[Pt]] = []
        var current: [Pt] = []
        for (a, b) in segments {
            if let last = current.last, (last - a).length < 0.01 {
                current.append(b)
            } else {
                if current.count >= 2 { polylines.append(current) }
                current = [a, b]
            }
        }
        if current.count >= 2 { polylines.append(current) }
        return polylines
    }

    /// Liang-Barsky: the parameter interval of segment a-b inside the rectangle, if any.
    private static func clip(_ a: Pt, _ b: Pt, _ r: (minX: Double, minY: Double, maxX: Double, maxY: Double)) -> (Double, Double)? {
        var t0 = 0.0, t1 = 1.0
        let d = b - a
        for (p, q) in [(-d.x, a.x - r.minX), (d.x, r.maxX - a.x), (-d.y, a.y - r.minY), (d.y, r.maxY - a.y)] {
            if abs(p) < 1e-9 {
                if q < 0 { return nil }
            } else {
                let t = q / p
                if p < 0 { if t > t1 { return nil }; t0 = max(t0, t) }
                else { if t < t0 { return nil }; t1 = min(t1, t) }
            }
        }
        return t0 < t1 ? (t0, t1) : nil
    }
}
