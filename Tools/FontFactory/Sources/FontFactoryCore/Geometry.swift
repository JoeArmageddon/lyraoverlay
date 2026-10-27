import Foundation

/// A point in font units (y up, baseline at 0).
public struct Pt: Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    static func + (a: Pt, b: Pt) -> Pt { Pt(a.x + b.x, a.y + b.y) }
    static func - (a: Pt, b: Pt) -> Pt { Pt(a.x - b.x, a.y - b.y) }
    static func * (a: Pt, k: Double) -> Pt { Pt(a.x * k, a.y * k) }
    var length: Double { (x * x + y * y).squareRoot() }
    var unit: Pt { let l = length; return l < 1e-9 ? Pt(0, 0) : Pt(x / l, y / l) }
    /// The left-hand normal.
    var normal: Pt { Pt(-y, x) }
    func dot(_ o: Pt) -> Double { x * o.x + y * o.y }
    func cross(_ o: Pt) -> Double { x * o.y - y * o.x }
}

typealias Contour = [Pt]

enum Geo {
    /// Signed area: positive for counter-clockwise (y up), negative for clockwise.
    static func area(_ c: Contour) -> Double {
        var a = 0.0
        for i in 0..<c.count {
            let p = c[i], q = c[(i + 1) % c.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    /// TrueType outer contours run clockwise. Every piece is oriented the same way so overlapping
    /// pieces union under the non-zero winding rule instead of cancelling.
    static func clockwise(_ c: Contour) -> Contour { area(c) > 0 ? c.reversed() : c }
    static func counterClockwise(_ c: Contour) -> Contour { area(c) < 0 ? c.reversed() : c }

    /// Drops degenerate pieces (too small to render) and tidies orientation.
    static func piece(_ c: Contour) -> Contour? {
        guard c.count >= 3, abs(area(c)) > 4 else { return nil }
        return clockwise(c)
    }

    /// A rectangle around segment a-b, `hw` to each side, optionally extended past either end.
    static func quad(_ a: Pt, _ b: Pt, hw: Double, extendA: Double = 0, extendB: Double = 0) -> Contour? {
        let d = (b - a).unit
        guard d.length > 0 else { return nil }
        let n = d.normal * hw
        let a2 = a - d * extendA, b2 = b + d * extendB
        return piece([a2 + n, b2 + n, b2 - n, a2 - n])
    }

    static func regular(center: Pt, radius: Double, sides: Int, rotation: Double = 0) -> Contour? {
        piece((0..<sides).map { i in
            let t = rotation + Double(i) / Double(sides) * 2 * .pi
            return Pt(center.x + cos(t) * radius, center.y + sin(t) * radius)
        })
    }

    /// The wedge that fills the outside of a bend at `cur`, so two butt-ended segments join cleanly.
    /// Falls back to a bevel when the miter would be longer than `miterLimit` stroke half-widths.
    static func joinWedge(prev: Pt, cur: Pt, next: Pt, hw: Double, miterLimit: Double) -> Contour? {
        let d1 = (cur - prev).unit, d2 = (next - cur).unit
        let turn = d1.cross(d2)
        guard abs(turn) > 1e-6 else { return nil }
        // The outer side of the bend is opposite the direction of the turn.
        let side: Double = turn > 0 ? -1 : 1
        let o1 = d1.normal * (hw * side), o2 = d2.normal * (hw * side)
        var pts: Contour = [cur, cur + o1]
        let denom = 1 + d1.dot(d2)
        if denom > 1e-6 {
            let miter = (o1 + o2) * (1 / denom)
            if miter.length <= hw * miterLimit { pts.append(cur + miter) }
        }
        pts.append(cur + o2)
        return piece(pts)
    }

    static func bbox(_ contours: [Contour]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var box: (Double, Double, Double, Double)?
        for c in contours { for p in c {
            if var b = box {
                b = (min(b.0, p.x), min(b.1, p.y), max(b.2, p.x), max(b.3, p.y)); box = b
            } else { box = (p.x, p.y, p.x, p.y) }
        } }
        return box.map { (minX: $0.0, minY: $0.1, maxX: $0.2, maxY: $0.3) }
    }

    /// Fillets the interior corners of a polyline: a corner with factor `k` > 0 becomes an arc of
    /// radius `radius * k`, drawn with `steps` segments per quarter turn. One step is a straight
    /// chamfer, many steps are round. Acute corners stay sharp.
    static func fillet(_ pts: [Pt], factors: [Double], closed: Bool, radius: Double, steps: Int) -> [Pt] {
        let n = pts.count
        guard n >= 3, radius > 0.5 else { return pts }
        var out: [Pt] = []
        for i in 0..<n {
            let isEnd = !closed && (i == 0 || i == n - 1)
            let k = factors[i]
            guard !isEnd, k > 0 else { out.append(pts[i]); continue }
            let prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            let v1 = prev - cur, v2 = next - cur
            let l1 = v1.length, l2 = v2.length
            guard l1 > 1e-6, l2 > 1e-6 else { out.append(cur); continue }
            let u1 = v1 * (1 / l1), u2 = v2 * (1 / l2)
            let cosA = max(-1, min(1, u1.dot(u2)))
            let alpha = acos(cosA)                // interior angle
            let turn = Double.pi - alpha          // how far the path turns
            guard turn > 0.05, turn <= 100 * .pi / 180 else { out.append(cur); continue }
            var rho = radius * k
            var t = rho / tan(alpha / 2)
            let limit = 0.48 * min(l1, l2)
            if t > limit { t = limit; rho = t * tan(alpha / 2) }
            guard t > 0.5 else { out.append(cur); continue }
            let t1 = cur + u1 * t, t2 = cur + u2 * t
            let bis = (u1 + u2).unit
            let center = cur + bis * (rho / sin(alpha / 2))
            let a0 = atan2(t1.y - center.y, t1.x - center.x)
            var a1 = atan2(t2.y - center.y, t2.x - center.x)
            // Take the short way round.
            var delta = a1 - a0
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            a1 = a0 + delta
            let segs = max(1, Int((Double(steps) * abs(delta) / (.pi / 2)).rounded(.up)))
            for s in 0...segs {
                let a = a0 + delta * Double(s) / Double(segs)
                out.append(Pt(center.x + cos(a) * rho, center.y + sin(a) * rho))
            }
        }
        return out
    }
}
