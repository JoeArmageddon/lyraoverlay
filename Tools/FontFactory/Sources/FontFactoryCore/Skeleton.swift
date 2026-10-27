import Foundation

/// A skeleton point in a glyph's own unit box: x 0...1 across, y 0...1 from baseline to cap line
/// (values outside that range reach below the baseline or above the cap line). `k` scales how much
/// the style's corner rounding applies at this vertex; 0 keeps it sharp.
struct SP {
    var x: Double
    var y: Double
    var k: Double
}

@inline(__always) func P(_ x: Double, _ y: Double, _ k: Double = 1) -> SP { SP(x: x, y: y, k: k) }

/// One stroke: an open or closed polyline of skeleton points, or a single point meaning a dot.
struct SStroke {
    var pts: [SP]
    var closed = false
    var isDot: Bool { pts.count == 1 }
}

func line(_ p: SP...) -> SStroke { SStroke(pts: p) }
func loop(_ p: SP...) -> SStroke { SStroke(pts: p, closed: true) }
func dot(_ x: Double, _ y: Double) -> SStroke { SStroke(pts: [P(x, y, 0)]) }

/// A normalized rectangle removed from the strokes (a stencil bridge).
struct Cut {
    var x0, y0, x1, y1: Double
}

struct SkelGlyph {
    /// Width of the glyph's box relative to the style's base width.
    var w: Double
    var strokes: [SStroke]
    var cuts: [Cut] = []

    func flippedVertically() -> SkelGlyph {
        SkelGlyph(w: w, strokes: strokes.map { s in
            SStroke(pts: s.pts.map { P($0.x, 1 - $0.y, $0.k) }, closed: s.closed)
        }, cuts: cuts.map { Cut(x0: $0.x0, y0: 1 - $0.y1, x1: $0.x1, y1: 1 - $0.y0) })
    }

    func mirroredHorizontally() -> SkelGlyph {
        SkelGlyph(w: w, strokes: strokes.map { s in
            SStroke(pts: s.pts.map { P(1 - $0.x, $0.y, $0.k) }, closed: s.closed)
        }, cuts: cuts.map { Cut(x0: 1 - $0.x1, y0: $0.y0, x1: 1 - $0.x0, y1: $0.y1) })
    }
}

private func g(_ w: Double, _ strokes: SStroke..., cuts: [Cut] = []) -> SkelGlyph {
    SkelGlyph(w: w, strokes: strokes, cuts: cuts)
}

/// A cut across a vertical edge at height `y` (a slit `h` tall), spanning x0...x1.
private func slit(_ x0: Double, _ x1: Double, _ y: Double, _ h: Double = 0.075) -> Cut {
    Cut(x0: x0, y0: y - h / 2, x1: x1, y1: y + h / 2)
}

enum Skeleton {
    /// The accent marks, by the character they are drawn on.
    enum Mark { case acute, grave, circumflex, diaeresis, tilde, ring, cedilla }

    /// accented character -> (base letter, mark)
    static let accented: [Character: (Character, Mark)] = {
        var m: [Character: (Character, Mark)] = [:]
        let table: [(String, Character, Mark)] = [
            ("áéíóúý", "A", .acute), ("àèìòù", "A", .grave), ("âêîôû", "A", .circumflex),
            ("äëïöüÿ", "A", .diaeresis), ("ãñõ", "A", .tilde), ("å", "A", .ring), ("ç", "C", .cedilla),
        ]
        // The base for each lowercase accented letter, in the order the strings above list them.
        let bases: [Mark: String] = [
            .acute: "AEIOUY", .grave: "AEIOU", .circumflex: "AEIOU", .diaeresis: "AEIOUY",
            .tilde: "ANO", .ring: "A", .cedilla: "C",
        ]
        for (letters, _, mark) in table {
            for (ch, base) in zip(letters, bases[mark]!) {
                m[ch] = (base, mark)
                m[Character(String(ch).uppercased())] = (base, mark)
            }
        }
        m["Ÿ"] = ("Y", .diaeresis)
        return m
    }()

    static let glyphs: [Character: SkelGlyph] = {
        var t: [Character: SkelGlyph] = [:]

        // Capitals. Strokes are written with sharp corners; the style rounds, chamfers or keeps them.
        t["A"] = g(1.0, line(P(0, 0, 0), P(0.5, 1, 0), P(1, 0, 0)), line(P(0.2, 0.36, 0), P(0.8, 0.36, 0)))
        t["B"] = g(1.0, line(P(0, 0, 0), P(0, 1, 0)),
                   line(P(0, 1, 0), P(0.78, 1), P(0.78, 0.52), P(0, 0.52, 0)),
                   line(P(0, 0.52, 0), P(0.96, 0.52), P(0.96, 0), P(0, 0, 0)),
                   cuts: [slit(0.6, 1.0, 0.76), slit(0.6, 1.05, 0.26)])
        t["C"] = g(1.0, line(P(1, 0.78, 0), P(1, 1), P(0, 1), P(0, 0), P(1, 0), P(1, 0.22, 0)))
        t["D"] = g(1.0, loop(P(0, 0, 0), P(0, 1, 0), P(1, 1, 1.7), P(1, 0, 1.7)), cuts: [slit(0.8, 1.1, 0.5)])
        t["E"] = g(0.9, line(P(1, 1, 0), P(0, 1, 0), P(0, 0, 0), P(1, 0, 0)), line(P(0, 0.5, 0), P(0.85, 0.5, 0)))
        t["F"] = g(0.85, line(P(1, 1, 0), P(0, 1, 0), P(0, 0, 0)), line(P(0, 0.5, 0), P(0.82, 0.5, 0)))
        t["G"] = g(1.0, line(P(1, 0.78, 0), P(1, 1), P(0, 1), P(0, 0), P(1, 0), P(1, 0.46, 0), P(0.52, 0.46, 0)))
        t["H"] = g(1.0, line(P(0, 0, 0), P(0, 1, 0)), line(P(1, 0, 0), P(1, 1, 0)), line(P(0, 0.5, 0), P(1, 0.5, 0)))
        t["I"] = g(0.62, line(P(0.5, 0, 0), P(0.5, 1, 0)), line(P(0.1, 1, 0), P(0.9, 1, 0)), line(P(0.1, 0, 0), P(0.9, 0, 0)))
        t["J"] = g(0.85, line(P(1, 1, 0), P(1, 0), P(0, 0), P(0, 0.3, 0)))
        t["K"] = g(1.0, line(P(0, 0, 0), P(0, 1, 0)), line(P(1, 1, 0), P(0, 0.45, 0), P(1, 0, 0)))
        t["L"] = g(0.85, line(P(0, 1, 0), P(0, 0), P(1, 0, 0)))
        t["M"] = g(1.25, line(P(0, 0, 0), P(0, 1, 0), P(0.5, 0.38, 0), P(1, 1, 0), P(1, 0, 0)))
        t["N"] = g(1.05, line(P(0, 0, 0), P(0, 1, 0), P(1, 0, 0), P(1, 1, 0)))
        t["O"] = g(1.05, loop(P(0, 0), P(1, 0), P(1, 1), P(0, 1)), cuts: [slit(-0.1, 0.25, 0.5), slit(0.75, 1.1, 0.5)])
        t["P"] = g(0.95, line(P(0, 0, 0), P(0, 1, 0), P(1, 1), P(1, 0.46), P(0, 0.46, 0)), cuts: [slit(0.7, 1.1, 0.73)])
        t["Q"] = g(1.05, loop(P(0, 0), P(1, 0), P(1, 1), P(0, 1)), line(P(0.58, 0.26, 0), P(1.04, -0.06, 0)),
                   cuts: [slit(-0.1, 0.25, 0.5), slit(0.75, 1.1, 0.62)])
        t["R"] = g(1.0, line(P(0, 0, 0), P(0, 1, 0), P(1, 1), P(1, 0.5), P(0, 0.5, 0)), line(P(0.45, 0.5, 0), P(1, 0, 0)),
                   cuts: [slit(0.7, 1.1, 0.75)])
        t["S"] = g(0.95, line(P(1, 0.72, 0), P(1, 1), P(0, 1), P(0, 0.5), P(1, 0.5), P(1, 0), P(0, 0), P(0, 0.28, 0)))
        t["T"] = g(1.0, line(P(0, 1, 0), P(1, 1, 0)), line(P(0.5, 1, 0), P(0.5, 0, 0)))
        t["U"] = g(1.0, line(P(0, 1, 0), P(0, 0), P(1, 0), P(1, 1, 0)))
        t["V"] = g(1.05, line(P(0, 1, 0), P(0.5, 0, 0), P(1, 1, 0)))
        t["W"] = g(1.4, line(P(0, 1, 0), P(0.25, 0, 0), P(0.5, 0.62, 0), P(0.75, 0, 0), P(1, 1, 0)))
        t["X"] = g(1.0, line(P(0, 1, 0), P(1, 0, 0)), line(P(1, 1, 0), P(0, 0, 0)))
        t["Y"] = g(1.0, line(P(0, 1, 0), P(0.5, 0.5, 0), P(1, 1, 0)), line(P(0.5, 0.5, 0), P(0.5, 0, 0)))
        t["Z"] = g(0.95, line(P(0, 1, 0), P(1, 1, 0), P(0, 0, 0), P(1, 0, 0)))

        // Digits.
        t["0"] = g(0.9, loop(P(0, 0), P(1, 0), P(1, 1), P(0, 1)), cuts: [slit(-0.1, 0.25, 0.5), slit(0.75, 1.1, 0.5)])
        t["1"] = g(0.7, line(P(0.08, 0.78, 0), P(0.55, 1, 0), P(0.55, 0, 0)), line(P(0.02, 0, 0), P(1, 0, 0)))
        t["2"] = g(0.95, line(P(0, 0.78, 0), P(0, 1), P(1, 1), P(1, 0.62), P(0, 0, 0), P(1, 0, 0)))
        t["3"] = g(0.95, line(P(0, 1, 0), P(1, 1), P(1, 0), P(0, 0, 0)), line(P(0.28, 0.5, 0), P(1, 0.5, 0)))
        t["4"] = g(1.0, line(P(0.74, 0, 0), P(0.74, 1, 0), P(0, 0.3, 0), P(1, 0.3, 0)))
        t["5"] = g(0.95, line(P(1, 1, 0), P(0, 1, 0), P(0, 0.52, 0.35), P(1, 0.52), P(1, 0), P(0, 0, 0)))
        t["6"] = g(0.95, line(P(1, 1, 0), P(0, 1), P(0, 0), P(1, 0), P(1, 0.5), P(0, 0.5, 0)), cuts: [slit(0.7, 1.1, 0.25)])
        t["7"] = g(0.95, line(P(0, 1, 0), P(1, 1, 0), P(0.38, 0, 0)))
        t["8"] = g(0.95, loop(P(0.06, 0.52), P(0.06, 1), P(0.94, 1), P(0.94, 0.52)), loop(P(0, 0), P(0, 0.52), P(1, 0.52), P(1, 0)),
                   cuts: [slit(-0.1, 0.3, 0.76), slit(0.7, 1.1, 0.26)])
        t["9"] = g(0.95, line(P(0, 0, 0), P(1, 0), P(1, 1), P(0, 1), P(0, 0.5), P(1, 0.5, 0)), cuts: [slit(-0.1, 0.3, 0.75)])

        // Punctuation and symbols.
        t["."] = g(0.28, dot(0.5, 0))
        t[","] = g(0.3, dot(0.5, 0), line(P(0.55, 0.02, 0), P(0.28, -0.22, 0)))
        t["!"] = g(0.3, line(P(0.5, 1, 0), P(0.5, 0.3, 0)), dot(0.5, 0))
        t["?"] = g(0.8, line(P(0, 0.78, 0), P(0, 1), P(1, 1), P(1, 0.62), P(0.5, 0.46), P(0.5, 0.3, 0)), dot(0.5, 0))
        t["'"] = g(0.28, line(P(0.5, 1, 0), P(0.5, 0.72, 0)))
        t["\""] = g(0.5, line(P(0.2, 1, 0), P(0.2, 0.72, 0)), line(P(0.8, 1, 0), P(0.8, 0.72, 0)))
        t["-"] = g(0.6, line(P(0.05, 0.45, 0), P(0.95, 0.45, 0)))
        t["\u{2013}"] = g(0.9, line(P(0.02, 0.45, 0), P(0.98, 0.45, 0)))
        t["\u{2014}"] = g(1.4, line(P(0.0, 0.45, 0), P(1.0, 0.45, 0)))
        t[":"] = g(0.28, dot(0.5, 0), dot(0.5, 0.62))
        t[";"] = g(0.3, dot(0.5, 0.62), dot(0.5, 0), line(P(0.55, 0.02, 0), P(0.28, -0.22, 0)))
        t["&"] = g(1.05, line(P(0.72, 0.72, 0), P(0.72, 1), P(0.1, 1), P(0.1, 0.62), P(0.95, 0, 0)),
                   line(P(0.55, 0.34, 0), P(0, 0.34), P(0, 0), P(0.7, 0), P(1, 0.3, 0)))
        t["("] = g(0.4, line(P(0.8, 1.05, 0), P(0.25, 0.78), P(0.25, 0.22), P(0.8, -0.05, 0)))
        t[")"] = t["("]!.mirroredHorizontally()
        t["["] = g(0.4, line(P(0.8, 1, 0), P(0.2, 1, 0), P(0.2, 0, 0), P(0.8, 0, 0)))
        t["]"] = t["["]!.mirroredHorizontally()
        t["{"] = g(0.45, line(P(0.85, 1, 0), P(0.5, 0.92, 0), P(0.5, 0.58, 0), P(0.15, 0.5, 0), P(0.5, 0.42, 0), P(0.5, 0.08, 0), P(0.85, 0, 0)))
        t["}"] = t["{"]!.mirroredHorizontally()
        t["<"] = g(0.8, line(P(0.95, 0.86, 0), P(0.05, 0.5, 0), P(0.95, 0.14, 0)))
        t[">"] = t["<"]!.mirroredHorizontally()
        t["/"] = g(0.7, line(P(0, 0, 0), P(1, 1, 0)))
        t["\\"] = t["/"]!.mirroredHorizontally()
        t["|"] = g(0.25, line(P(0.5, -0.15, 0), P(0.5, 1.05, 0)))
        t["#"] = g(1.0, line(P(0.34, 0.04, 0), P(0.34, 0.96, 0)), line(P(0.68, 0.04, 0), P(0.68, 0.96, 0)),
                   line(P(0.04, 0.34, 0), P(0.98, 0.34, 0)), line(P(0.04, 0.66, 0), P(0.98, 0.66, 0)))
        t["@"] = g(1.15, line(P(0.9, 0.22, 0), P(0.9, 0), P(0, 0), P(0, 1), P(1, 1), P(1, 0.32, 0), P(0.7, 0.32, 0)),
                   loop(P(0.32, 0.3), P(0.32, 0.7), P(0.7, 0.7), P(0.7, 0.3)))
        t["%"] = g(1.15, line(P(0.08, 0.02, 0), P(0.92, 0.98, 0)),
                   loop(P(0, 0.62), P(0, 1), P(0.34, 1), P(0.34, 0.62)), loop(P(0.66, 0), P(0.66, 0.38), P(1, 0.38), P(1, 0)))
        t["+"] = g(0.8, line(P(0.08, 0.5, 0), P(0.92, 0.5, 0)), line(P(0.5, 0.15, 0), P(0.5, 0.85, 0)))
        t["="] = g(0.8, line(P(0.08, 0.36, 0), P(0.92, 0.36, 0)), line(P(0.08, 0.64, 0), P(0.92, 0.64, 0)))
        t["$"] = g(0.95, line(P(1, 0.72, 0), P(1, 1), P(0, 1), P(0, 0.5), P(1, 0.5), P(1, 0), P(0, 0), P(0, 0.28, 0)),
                   line(P(0.5, 1.1, 0), P(0.5, -0.1, 0)))
        t["*"] = g(0.7, line(P(0.5, 0.95, 0), P(0.5, 0.45, 0)), line(P(0.12, 0.85, 0), P(0.88, 0.55, 0)), line(P(0.12, 0.55, 0), P(0.88, 0.85, 0)))
        t["_"] = g(0.9, line(P(0, -0.18, 0), P(1, -0.18, 0)))
        t["~"] = g(0.9, line(P(0, 0.42, 0), P(0.25, 0.62, 0), P(0.75, 0.38, 0), P(1, 0.58, 0)))
        t["^"] = g(0.8, line(P(0.05, 0.55, 0), P(0.5, 1, 0), P(0.95, 0.55, 0)))
        t["\u{2026}"] = g(1.3, dot(0.15, 0), dot(0.5, 0), dot(0.85, 0))
        t["\u{00B0}"] = g(0.5, loop(P(0.1, 0.68), P(0.1, 1), P(0.9, 1), P(0.9, 0.68)))
        t["\u{00A1}"] = t["!"]!.flippedVertically()
        t["\u{00BF}"] = t["?"]!.flippedVertically()
        // Curly quotes share the straight forms.
        t["\u{2018}"] = t["'"]; t["\u{2019}"] = t["'"]
        t["\u{201C}"] = t["\""]; t["\u{201D}"] = t["\""]
        return t
    }()

    /// Characters every font must provide.
    static let required: [Character] = {
        var chars: [Character] = []
        for u in UnicodeScalar("A").value...UnicodeScalar("Z").value { chars.append(Character(UnicodeScalar(u)!)) }
        for u in UnicodeScalar("a").value...UnicodeScalar("z").value { chars.append(Character(UnicodeScalar(u)!)) }
        chars += Array("0123456789")
        chars += Array(".,!?'\"-:;&()/#@%+=$*_~^<>[]{}|\\ ")
        chars += Array("\u{2026}\u{2013}\u{2014}\u{2018}\u{2019}\u{201C}\u{201D}\u{00A1}\u{00BF}\u{00B0}")
        chars += Array("áàâäãåéèêëíìîïóòôöõúùûüñçýÿÁÀÂÄÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇÝŸ")
        return chars
    }()
}
