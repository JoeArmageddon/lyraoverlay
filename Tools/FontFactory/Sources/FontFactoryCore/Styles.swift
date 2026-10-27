import Foundation

/// Everything that makes one original font look the way it does.
public struct StyleParams {
    public var name: String
    public var weightClass: Int
    /// Half the stroke width, in font units.
    public var hw: Double
    /// Outer width of a glyph whose skeleton width is 1.0.
    public var baseW: Double
    /// Corner rounding radius; with `arcSteps` of 1 a corner becomes a straight chamfer.
    public var radius: Double
    public var arcSteps: Int
    /// Slant as a tangent: x shifts by `shear * y`.
    public var shear: Double
    public var cap: CapStyle
    public var join: JoinStyle
    public var dot: DotStyle
    public var teeth: Teeth?
    public var cornerThorn: Double?
    /// Space between a glyph's outline and its advance edge, each side.
    public var sidebearing: Double
    public var spaceWidth: Double
    /// Cut stencil bridges into the strokes that define them.
    public var useCuts: Bool
    public var slashZero: Bool
    /// Lowercase letters are small capitals: this scales their width, `xHeight` sets their height.
    public var smallCapsX: Double
    public var xHeight: Double
    public var isPixel: Bool

    public var family: String { "Lyra \(name)" }
    public var postScriptName: String { "Lyra" + name.replacingOccurrences(of: " ", with: "") + "-Regular" }
    public var fileName: String { postScriptName + ".ttf" }

    public init(name: String, weightClass: Int, hw: Double, baseW: Double, radius: Double = 0, arcSteps: Int = 1,
                shear: Double = 0, cap: CapStyle = .butt, join: JoinStyle = .miter(2), dot: DotStyle = .square,
                teeth: Teeth? = nil, cornerThorn: Double? = nil, sidebearing: Double = 45, spaceWidth: Double = 300,
                useCuts: Bool = false, slashZero: Bool = false, smallCapsX: Double = 0.9, xHeight: Double = 520, isPixel: Bool = false) {
        self.name = name; self.weightClass = weightClass; self.hw = hw; self.baseW = baseW
        self.radius = radius; self.arcSteps = arcSteps; self.shear = shear; self.cap = cap; self.join = join
        self.dot = dot; self.teeth = teeth; self.cornerThorn = cornerThorn; self.sidebearing = sidebearing
        self.spaceWidth = spaceWidth; self.useCuts = useCuts; self.slashZero = slashZero
        self.smallCapsX = smallCapsX; self.xHeight = xHeight; self.isPixel = isPixel
    }
}

public enum Styles {
    public static let forge = StyleParams(
        name: "Forge", weightClass: 800, hw: 60, baseW: 500, radius: 150, arcSteps: 1,
        cap: .spike(112), join: .miter(2.2), dot: .diamond,
        teeth: Teeth(pitch: 168, width: 128, height: 68, margin: 74, minLength: 250, variation: 0.6),
        sidebearing: 50, spaceWidth: 280)

    public static let blade = StyleParams(
        name: "Blade", weightClass: 600, hw: 34, baseW: 470, radius: 70, arcSteps: 1, shear: 0.22,
        cap: .taper(150), join: .miter(3.4), dot: .spike, sidebearing: 38, spaceWidth: 260, smallCapsX: 0.92)

    public static let stencil = StyleParams(
        name: "Stencil Ops", weightClass: 800, hw: 62, baseW: 500, radius: 46, arcSteps: 1,
        cap: .butt, join: .miter(2), dot: .square, sidebearing: 54, spaceWidth: 290, useCuts: true)

    public static let circuit = StyleParams(
        name: "Circuit", weightClass: 400, hw: 30, baseW: 500, radius: 130, arcSteps: 1,
        cap: .pad(112), join: .miter(2), dot: .square, sidebearing: 60, spaceWidth: 290, slashZero: true)

    public static let neon = StyleParams(
        name: "Neon Tube", weightClass: 700, hw: 48, baseW: 600, radius: 280, arcSteps: 6,
        cap: .round, join: .round, dot: .circle, sidebearing: 66, spaceWidth: 340, smallCapsX: 0.9)

    public static let thorn = StyleParams(
        name: "Thorn", weightClass: 300, hw: 20, baseW: 420, radius: 60, arcSteps: 1,
        cap: .spike(120), join: .miter(5), dot: .diamond, cornerThorn: 54, sidebearing: 54, spaceWidth: 270, smallCapsX: 0.94)

    public static let monoline = StyleParams(
        name: "Monoline Round", weightClass: 300, hw: 22, baseW: 400, radius: 200, arcSteps: 6,
        cap: .round, join: .round, dot: .circle, sidebearing: 44, spaceWidth: 250, smallCapsX: 0.95)

    public static let pixel = StyleParams(
        name: "Pixel", weightClass: 400, hw: 50, baseW: 500, sidebearing: 50, spaceWidth: 400, xHeight: 700, isPixel: true)

    public static let all: [StyleParams] = [forge, blade, stencil, circuit, neon, thorn, monoline, pixel]
}

// MARK: - Building glyphs

struct GlyphBuilder {
    let style: StyleParams
    static let capHeight = 700.0

    func glyph(for ch: Character) -> GlyphData? {
        if ch == " " { return GlyphData(contours: [], advance: Int(style.spaceWidth)) }
        if style.isPixel { return pixelGlyph(for: ch) }

        if let g = Skeleton.glyphs[ch] { return render(g, ch: ch, lower: false, mark: nil) }
        if ch.isASCII, ch.isLowercase, let g = Skeleton.glyphs[Character(ch.uppercased())] {
            return render(g, ch: ch, lower: true, mark: nil)
        }
        if let (base, mark) = Skeleton.accented[ch], let g = Skeleton.glyphs[base] {
            return render(g, ch: ch, lower: ch.isLowercase, mark: mark)
        }
        return nil
    }

    // MARK: Stroke-based styles

    private func render(_ g: SkelGlyph, ch: Character, lower: Bool, mark: Skeleton.Mark?) -> GlyphData {
        let s = style
        let height = lower ? s.xHeight : Self.capHeight
        let proportion = lower ? min(s.smallCapsX, s.xHeight / Self.capHeight) : 1
        let boxW = max(s.baseW * g.w * (lower ? s.smallCapsX : 1), 2 * s.hw + 20)
        let rangeX = max(boxW - 2 * s.hw, 0)
        let rangeY = height - 2 * s.hw

        func map(_ p: SP) -> Pt { Pt(s.hw + p.x * rangeX, s.hw + p.y * rangeY) }
        func shear(_ p: Pt) -> Pt { Pt(p.x + p.y * s.shear, p.y) }

        let seed = Int(ch.unicodeScalars.first!.value)
        var polylines: [(pts: [Pt], closed: Bool)] = []
        var dots: [Pt] = []

        for stroke in g.strokes {
            if stroke.isDot { dots.append(map(stroke.pts[0])); continue }
            let pts = stroke.pts.map(map)
            let filleted = Geo.fillet(pts, factors: stroke.pts.map(\.k), closed: stroke.closed,
                                      radius: s.radius * proportion, steps: s.arcSteps)
            polylines.append((filleted, stroke.closed))
        }
        if s.slashZero, ch == "0" {
            polylines.append(([map(P(0.3, 0.3)), map(P(0.7, 0.7))], false))
        }

        // Butt-ended and tapered strokes stop at their end points, which would leave stems a
        // stroke-width short of the cap line (a razor tip should still reach it). Extend the open ends first (stencil cuts are made afterwards, so a cut
        // still leaves a clean square end).
        var extendsEnds = false
        switch s.cap { case .butt, .taper: extendsEnds = true; default: break }
        if extendsEnds {
            polylines = polylines.map { pl in
                guard !pl.closed, pl.pts.count >= 2 else { return pl }
                var pts = pl.pts
                let n = pts.count
                pts[0] = pts[0] + (pts[0] - pts[1]).unit * s.hw
                pts[n - 1] = pts[n - 1] + (pts[n - 1] - pts[n - 2]).unit * s.hw
                return (pts: pts, closed: false)
            }
        }

        if s.useCuts, !g.cuts.isEmpty {
            let rects = g.cuts.map { c -> (minX: Double, minY: Double, maxX: Double, maxY: Double) in
                let a = map(P(c.x0, c.y0)), b = map(P(c.x1, c.y1))
                return (min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))
            }
            polylines = polylines.flatMap { pl in
                Clipper.cut(pl.pts, closed: pl.closed, rects: rects).map { (pts: $0, closed: false) }
            }
        }

        let stroker = Stroker(hw: s.hw, cap: s.cap, join: s.join, dot: s.dot, teeth: s.teeth, cornerThorn: s.cornerThorn)
        let center = Pt(boxW / 2, height / 2)
        var contours: [Contour] = []
        for (i, pl) in polylines.enumerated() {
            contours += stroker.pieces(for: pl.pts, closed: pl.closed, center: center, seed: seed &* 17 &+ i)
        }
        for d in dots { contours += stroker.dotPieces(at: d) }

        if let mark { contours += markPieces(mark, centerX: boxW / 2, top: height, stroker: stroker) }

        // Slant everything, then place the glyph so its left edge sits one sidebearing in.
        if s.shear != 0 { contours = contours.map { $0.map(shear) } }
        return finish(contours)
    }

    private func markPieces(_ mark: Skeleton.Mark, centerX cx: Double, top: Double, stroker base: Stroker) -> [Contour] {
        // Marks are drawn lighter than the letter so they don't turn into blobs on heavy styles.
        let hwM = min(base.hw, 34) * 0.85
        let scale = hwM / base.hw
        var m = base
        m.hw = hwM
        m.teeth = nil
        m.cornerThorn = nil
        switch base.cap {
        case .spike(let l): m.cap = .spike(l * scale)
        case .taper(let l): m.cap = .taper(l * scale)
        case .pad(let p): m.cap = .pad(p * scale)
        default: break
        }
        let y0 = top + 55 + hwM
        switch mark {
        case .acute:
            return m.pieces(for: [Pt(cx - 42, y0), Pt(cx + 42, y0 + 92)], closed: false, center: Pt(cx, y0), seed: 1)
        case .grave:
            return m.pieces(for: [Pt(cx + 42, y0), Pt(cx - 42, y0 + 92)], closed: false, center: Pt(cx, y0), seed: 2)
        case .circumflex:
            return m.pieces(for: [Pt(cx - 58, y0), Pt(cx, y0 + 84), Pt(cx + 58, y0)], closed: false, center: Pt(cx, y0), seed: 3)
        case .diaeresis:
            return m.dotPieces(at: Pt(cx - 58, y0 + 20)) + m.dotPieces(at: Pt(cx + 58, y0 + 20))
        case .tilde:
            return m.pieces(for: [Pt(cx - 66, y0 + 8), Pt(cx - 28, y0 + 52), Pt(cx + 28, y0 + 8), Pt(cx + 66, y0 + 52)],
                            closed: false, center: Pt(cx, y0), seed: 4)
        case .ring:
            let r = 40.0
            return m.pieces(for: [Pt(cx - r, y0 + 8), Pt(cx - r, y0 + 8 + 2 * r), Pt(cx + r, y0 + 8 + 2 * r), Pt(cx + r, y0 + 8)],
                            closed: true, center: Pt(cx, y0 + r), seed: 5)
        case .cedilla:
            return m.pieces(for: [Pt(cx, base.hw), Pt(cx, -62), Pt(cx - 52, -102)], closed: false, center: Pt(cx, -20), seed: 6)
        }
    }

    private func finish(_ contours: [Contour]) -> GlyphData {
        guard let box = Geo.bbox(contours) else { return GlyphData(contours: [], advance: Int(style.spaceWidth / 2)) }
        let dx = style.sidebearing - box.minX
        let moved = contours.map { $0.map { Pt($0.x + dx, $0.y) } }
        let advance = (box.maxX - box.minX) + 2 * style.sidebearing
        return GlyphData(contours: moved, advance: Int(advance.rounded()))
    }

    // MARK: Pixel style

    private func pixelGlyph(for ch: Character) -> GlyphData? {
        let cell = 100.0
        var bitmap: Bitmap?
        var mark: Skeleton.Mark?
        if let b = PixelData.glyphs[ch] { bitmap = b }
        else if ch.isASCII, ch.isLowercase { bitmap = PixelData.glyphs[Character(ch.uppercased())] }
        else if let (base, m) = Skeleton.accented[ch] { bitmap = PixelData.glyphs[base]; mark = m }
        guard var bm = bitmap else { return nil }

        var rows = bm.rows
        var below = bm.below
        if let mark {
            if mark == .cedilla {
                rows.append("..#..")
                below += 1
            } else {
                let markRows = PixelData.marks[mark] ?? []
                rows = markRows + [String(repeating: ".", count: 5)] + rows
            }
        }
        bm = Bitmap(rows: rows, below: below)
        let width = Double(bm.width)
        let baselineRow = rows.count - below   // row boundary index, from the top, where y = 0
        var contours: [Contour] = []
        for (r, row) in rows.enumerated() {
            let top = Double(baselineRow - r) * cell
            let bottom = top - cell
            let chars = Array(row)
            var c = 0
            while c < chars.count {
                guard chars[c] == "#" else { c += 1; continue }
                var e = c
                while e + 1 < chars.count, chars[e + 1] == "#" { e += 1 }
                // A hair of overlap so neighbouring rows fuse instead of leaving seams.
                let x0 = Double(c) * cell - 1, x1 = Double(e + 1) * cell + 1
                if let piece = Geo.piece([Pt(x0, bottom - 1), Pt(x0, top + 1), Pt(x1, top + 1), Pt(x1, bottom - 1)]) { contours.append(piece) }
                c = e + 1
            }
        }
        let moved = contours.map { $0.map { Pt($0.x + style.sidebearing, $0.y) } }
        return GlyphData(contours: moved, advance: Int(width * cell + 2 * style.sidebearing))
    }
}

// MARK: - Whole fonts

public enum FontFactory {
    public static let copyright = "Copyright (c) 2026 Lyra project. All rights reserved."
    public static let license = "This Font Software is licensed under the SIL Open Font License, Version 1.1."
    public static let licenseURL = "https://openfontlicense.org"

    public struct Result {
        public var style: StyleParams
        public var data: Data
        public var glyphCount: Int
        public var missing: [Character]
    }

    public static func metadata(for style: StyleParams) -> FontMetadata {
        FontMetadata(family: style.family, postScriptName: style.postScriptName, copyright: copyright,
                     license: license, licenseURL: licenseURL, designer: "Lyra project",
                     weightClass: style.weightClass, isMonospaced: false,
                     italicAngle: style.shear == 0 ? 0 : -atan(style.shear) * 180 / .pi,
                     xHeight: Int(style.xHeight), capHeight: 700)
    }

    public static func make(_ style: StyleParams) -> Result {
        let builder = GlyphBuilder(style: style)
        var glyphs: [UInt32: GlyphData] = [:]
        var missing: [Character] = []
        for ch in Skeleton.required {
            guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { continue }
            if let g = builder.glyph(for: ch) { glyphs[scalar.value] = g } else { missing.append(ch) }
        }
        let output = TTFWriter.write(meta: metadata(for: style), notdef: notdef(), glyphs: glyphs)
        return Result(style: style, data: output.data, glyphCount: output.glyphCount, missing: missing)
    }

    /// The box shown for characters a font lacks: a frame with a hole (the inner contour runs the other way).
    static func notdef() -> GlyphData {
        let outer: Contour = [Pt(60, 0), Pt(60, 700), Pt(440, 700), Pt(440, 0)]
        let inner: Contour = [Pt(120, 60), Pt(380, 60), Pt(380, 640), Pt(120, 640)]
        return GlyphData(contours: [Geo.clockwise(outer), Geo.counterClockwise(inner)], advance: 500)
    }
}
