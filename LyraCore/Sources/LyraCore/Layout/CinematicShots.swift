import Foundation
import CoreGraphics

// The building blocks of the Cinematic style: shot templates (where each word goes), camera moves,
// and transitions. Everything here is pure and deterministic: the same line always becomes the
// same shot, with no randomness and no state between frames.

/// How a line is composed on screen.
enum ShotTemplate: Int, CaseIterable, Sendable {
    /// One huge hero word, with the rest of the line small and widely tracked above and below it.
    case hero
    /// Words stacked down the left margin, the hero much larger than the rest.
    case stackLeft
    /// The same, down the right margin.
    case stackRight
    /// First half of the line upper left, second half lower right, the hero largest.
    case diagonal
    /// A small tracked line of context on top, the hero word beneath it like a title.
    case titleCard
    /// Phrases dropped into a loose grid, each appearing as it is sung.
    case scatter
    /// A justified poster block that fills the frame.
    case wall

    var name: String {
        switch self {
        case .hero: return "hero"
        case .stackLeft: return "stackLeft"
        case .stackRight: return "stackRight"
        case .diagonal: return "diagonal"
        case .titleCard: return "titleCard"
        case .scatter: return "scatter"
        case .wall: return "wall"
        }
    }
}

/// The slow move the camera makes across a shot.
enum CameraMove: Int, CaseIterable, Sendable {
    case pushIn, pullOut, panLeft, panRight, panUp, drift
}

/// How a shot arrives.
enum ShotTransition: Int, CaseIterable, Sendable {
    /// Instant.
    case cut
    /// Slides in sideways, blurred, and snaps into focus.
    case whip
    /// Starts too close and blurred, and pulls back into place.
    case zoomThrough
    /// Rises a little and settles.
    case riseSettle

    /// Seconds the arrival takes; every transition is quick so lines never feel slow.
    var duration: Double {
        switch self {
        case .cut: return 0
        case .whip: return 0.18
        case .zoomThrough: return 0.25
        case .riseSettle: return 0.22
        }
    }

    var name: String {
        switch self {
        case .cut: return "cut"
        case .whip: return "whip"
        case .zoomThrough: return "zoomThrough"
        case .riseSettle: return "riseSettle"
        }
    }
}

/// One item of a shot, in settled position (before the camera and the transition).
struct ShotWord {
    var text: String
    var font: FontSpec
    var width: CGFloat
    var height: CGFloat
    var center: CGPoint
    /// Seconds after the shot starts before this item begins to arrive.
    var delay: Double
    var isEmphasis: Bool
    /// The line's word indices this item covers: one word, or several for a phrase.
    var covers: Range<Int>
    /// True when the item stays hidden until its first word starts being sung.
    var appearsWhenSung: Bool
}

struct Shot {
    var template: ShotTemplate
    var camera: CameraMove
    var transition: ShotTransition
    /// +1 or -1: which side a whip comes from.
    var side: Double
    var seed: UInt64
    var words: [ShotWord]
}

/// A tiny seeded generator, so layouts that look random are the same every frame.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// 0..<1
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

enum CinematicShots {
    // MARK: - Hashing and choices

    /// FNV-1a with a final mix. Swift's own `Hasher` is randomized per process, which would make
    /// the same song compose differently on every launch.
    static func hash(_ text: String, salt: UInt64 = 0) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325 ^ (salt &* 0x9E3779B97F4A7C15)
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        h ^= h >> 33
        h = h &* 0xff51afd7ed558ccd
        h ^= h >> 33
        return h
    }

    static func seed(forLine index: Int, texts: [String]) -> UInt64 {
        hash(texts.joined(separator: " "), salt: UInt64(index) &+ 1)
    }

    /// How well each template suits a line of this size, before the per-line jitter.
    static func baseScore(_ template: ShotTemplate, words n: Int) -> Double {
        switch template {
        case .hero:       return n <= 2 ? 2.2 : (n <= 6 ? 1.2 : (n <= 8 ? 0.5 : 0.15))
        // A stack or a title card of a very long line shrinks to unreadable text, so only the wall,
        // a scatter of phrases, or a poor diagonal compete there.
        case .titleCard:  return n < 3 ? 0.25 : (n <= 7 ? 1.3 : 0.1)
        case .stackLeft:  return n <= 2 ? 0.9 : (n <= 8 ? 1.2 : 0.1)
        case .stackRight: return n <= 2 ? 0.85 : (n <= 8 ? 1.15 : 0.1)
        case .diagonal:   return n < 2 ? 0 : (n <= 9 ? 1.2 : 0)
        case .scatter:    return n < 3 ? 0 : (n <= 9 ? 1.1 : 0.4)
        case .wall:       return n <= 2 ? 0.9 : (n <= 5 ? 0.5 : (n <= 8 ? 1.0 : 1.7))
        }
    }

    /// How much to discourage a template that was used 1, 2, 3 or 4 shots ago, so a song doesn't
    /// settle into two or three favourites.
    private static let recencyPenalty = [Double.infinity, 1.3, 0.8, 0.4]

    /// The template for line `index`: the best fit for its size with a deterministic nudge, never
    /// the same as the shot before. "The shot before" is the previous line that has words, so the
    /// choice is a chain from the first line and is stable no matter where playback starts.
    static func template(forLine index: Int, in lines: [LyricLine]) -> ShotTemplate {
        var history: [ShotTemplate] = []   // shots so far, oldest first
        for i in 0...max(0, min(index, lines.count - 1)) {
            let texts = lines[i].words.map(\.text)
            guard !texts.isEmpty else { continue }
            let s = seed(forLine: i, texts: texts)
            var best: (template: ShotTemplate, score: Double)?
            for t in ShotTemplate.allCases {
                var penalty = 0.0
                for (back, p) in recencyPenalty.enumerated() where history.count > back && history[history.count - 1 - back] == t {
                    penalty += p
                }
                guard penalty.isFinite else { continue }   // never the same shot twice in a row
                // Jitter spreads equal fits around; the rotation term makes neighbours differ.
                let jitter = Double(hash(t.name, salt: s) % 1000) / 1000 * 0.8
                let rotation = Double((i + t.rawValue) % 7) * 0.04
                let score = baseScore(t, words: texts.count) + jitter + rotation - penalty
                if best == nil || score > best!.score { best = (t, score) }
            }
            history.append(best?.template ?? .hero)
        }
        return history.last ?? .hero
    }

    static func camera(seed: UInt64) -> CameraMove {
        CameraMove.allCases[Int(hash("camera", salt: seed) % UInt64(CameraMove.allCases.count))]
    }

    /// Cuts are rarer than the moving transitions.
    static func transition(seed: UInt64) -> ShotTransition {
        let pool: [ShotTransition] = [.whip, .zoomThrough, .riseSettle, .cut, .whip, .zoomThrough, .riseSettle]
        return pool[Int(hash("transition", salt: seed) % UInt64(pool.count))]
    }

    static func side(seed: UInt64) -> Double { hash("side", salt: seed) % 2 == 0 ? 1 : -1 }

    // MARK: - Building a shot

    static func build(_ template: ShotTemplate, texts: [String], hero: Int, seed: UInt64, ctx: ShotContext) -> [ShotWord] {
        switch template {
        case .hero: return heroShot(texts, hero: hero, seed: seed, ctx: ctx)
        case .stackLeft: return stack(texts, hero: hero, alignRight: false, ctx: ctx)
        case .stackRight: return stack(texts, hero: hero, alignRight: true, ctx: ctx)
        case .diagonal: return diagonal(texts, hero: hero, ctx: ctx)
        case .titleCard: return titleCard(texts, hero: hero, ctx: ctx)
        case .scatter: return scatter(texts, hero: hero, seed: seed, ctx: ctx)
        case .wall: return wall(texts, hero: hero, ctx: ctx)
        }
    }

    // MARK: - hero

    private static func heroShot(_ texts: [String], hero h: Int, seed: UInt64, ctx: ShotContext) -> [ShotWord] {
        let W = ctx.width, H = ctx.height
        var rng = SplitMix64(state: seed)
        let fraction = 0.55 + 0.15 * rng.unit()
        let heroUnit = ctx.unitWidth(texts[h])
        var heroSize = min(Double(fraction * W) / heroUnit, Double(0.46 * H))
        heroSize = max(heroSize, ctx.baseSize * 1.4)
        heroSize = min(heroSize, Double(ctx.maxWordWidth) / heroUnit)

        let supportTrack = 0.18
        // Small next to the hero, but still readable on a big screen: never under 5% of the height.
        let supportSize = max(ctx.baseSize * 0.9, Double(0.05 * H))
        let pre = Array(0..<h), post = Array((h + 1)..<texts.count)
        let preSize = pre.isEmpty ? 0 : ctx.fitRowSize(pre, texts, size: supportSize, trackingAdd: supportTrack, maxWidth: 0.8 * W)
        let postSize = post.isEmpty ? 0 : ctx.fitRowSize(post, texts, size: supportSize, trackingAdd: supportTrack, maxWidth: 0.8 * W)

        let heroH = ctx.lineHeightUnit * heroSize * 0.84
        let preH = pre.isEmpty ? 0 : ctx.lineHeightUnit * preSize
        let postH = post.isEmpty ? 0 : ctx.lineHeightUnit * postSize
        let gap = ctx.baseSize * 0.3
        let total = preH + (pre.isEmpty ? 0 : gap) + heroH + (post.isEmpty ? 0 : gap) + postH
        var y = H * 0.48 - total / 2

        var out: [ShotWord] = []
        if !pre.isEmpty {
            out += ctx.row(pre, texts, size: preSize, trackingAdd: supportTrack, align: .center(W / 2), y: y + preH / 2, delayStart: 0.05)
            y += preH + gap
        }
        out.append(ctx.word(texts[h], index: h, size: heroSize, center: CGPoint(x: W / 2, y: y + heroH / 2), delay: 0, emphasis: true))
        y += heroH + gap
        if !post.isEmpty {
            out += ctx.row(post, texts, size: postSize, trackingAdd: supportTrack, align: .center(W / 2), y: y + postH / 2, delayStart: 0.09)
        }
        return out
    }

    // MARK: - stacks

    private static func stack(_ texts: [String], hero h: Int, alignRight: Bool, ctx: ShotContext) -> [ShotWord] {
        let W = ctx.width, H = ctx.height
        let margin = 0.07 * W
        // Relative sizes (the hero 2.2x), then one scale for the whole stack: big enough to fill
        // about 62% of the frame's height, but no word wider than the frame allows, the hero no
        // taller than 30% of it, and never so large that a short stack looks like a poster.
        let weights = texts.indices.map { $0 == h ? 2.2 : 1.0 }
        let leading = 0.9
        let atBase = zip(weights, texts).reduce(0.0) { $0 + ctx.lineHeightUnit * ctx.baseSize * $1.0 * leading }
        var k = Double(0.62 * H) / atBase
        for (i, text) in texts.enumerated() {
            k = min(k, Double(ctx.maxWordWidth) / (ctx.unitWidth(text) * ctx.baseSize * weights[i]))
        }
        k = min(k, Double(0.3 * H) / (ctx.baseSize * 2.2), 2.4)
        let sizes = weights.map { ctx.baseSize * $0 * k }
        let total = sizes.reduce(0) { $0 + ctx.lineHeightUnit * $1 * leading }

        var y = H / 2 - total / 2
        var out: [ShotWord] = []
        for (i, text) in texts.enumerated() {
            let rowH = ctx.lineHeightUnit * sizes[i] * leading
            let w = ctx.unitWidth(text) * sizes[i]
            let x = alignRight ? W - margin - w / 2 : margin + w / 2
            out.append(ctx.word(text, index: i, size: sizes[i], center: CGPoint(x: x, y: y + rowH / 2),
                                delay: min(0.035 * Double(i), 0.15), emphasis: i == h))
            y += rowH
        }
        return out
    }

    // MARK: - diagonal

    private static func diagonal(_ texts: [String], hero h: Int, ctx: ShotContext) -> [ShotWord] {
        let W = ctx.width, H = ctx.height
        let split = (texts.count + 1) / 2
        let first = Array(0..<split), second = Array(split..<texts.count)
        let margin = 0.07 * W
        var out: [ShotWord] = []

        // The hero is 2x its neighbours. One size serves both groups: as large as lets the wider
        // group fill about 72% of the width, with the hero no taller than 26% of the frame, so a
        // two-word line is bold and a nine-word line still fits.
        let heroScale = 2.0
        func widthPerPoint(_ indices: [Int]) -> Double {
            indices.reduce(0.0) { $0 + ctx.unitWidth(texts[$1]) * ($1 == h ? heroScale : 1) }
                + Double(max(0, indices.count - 1)) * 0.28
        }
        let maxW = Double(0.72 * W)
        let widest = max(widthPerPoint(first), widthPerPoint(second), 0.0001)
        let shared = min(maxW / widest, Double(0.26 * H) / heroScale, ctx.baseSize * 2.6)

        func group(_ indices: [Int], alignRight: Bool, y: CGFloat, delayStart: Double) {
            guard !indices.isEmpty else { return }
            let size = shared, heroSize = shared * heroScale
            func rowWidth(_ s: Double, _ hs: Double) -> Double {
                indices.reduce(0.0) { $0 + ctx.unitWidth(texts[$1]) * ($1 == h ? hs : s) }
                    + Double(max(0, indices.count - 1)) * 0.28 * s
            }

            var x = alignRight ? W - margin - CGFloat(rowWidth(size, heroSize)) : margin
            for (n, i) in indices.enumerated() {
                let s = i == h ? heroSize : size
                let w = CGFloat(ctx.unitWidth(texts[i]) * s)
                out.append(ctx.word(texts[i], index: i, size: s, center: CGPoint(x: x + w / 2, y: y),
                                    delay: delayStart + 0.03 * Double(n), emphasis: i == h))
                x += w + CGFloat(0.28 * size)
            }
        }
        group(first, alignRight: false, y: 0.30 * H, delayStart: 0)
        group(second, alignRight: true, y: 0.70 * H, delayStart: 0.1)
        return out.sorted { $0.covers.lowerBound < $1.covers.lowerBound }
    }

    // MARK: - titleCard

    private static func titleCard(_ texts: [String], hero h: Int, ctx: ShotContext) -> [ShotWord] {
        let W = ctx.width, H = ctx.height
        let context = texts.indices.filter { $0 != h }
        let track = 0.34
        let supportSize = context.isEmpty ? 0 : ctx.fitRowSize(context, texts, size: max(ctx.baseSize * 0.75, Double(0.045 * H)), trackingAdd: track, maxWidth: 0.78 * W)
        let heroUnit = ctx.unitWidth(texts[h])
        var heroSize = min(Double(0.44 * W) / heroUnit, Double(0.36 * H))
        heroSize = max(heroSize, ctx.baseSize * 1.5)
        heroSize = min(heroSize, Double(ctx.maxWordWidth) / heroUnit)

        let supportH = context.isEmpty ? 0 : ctx.lineHeightUnit * supportSize
        let heroH = ctx.lineHeightUnit * heroSize * 0.84
        let gap = ctx.baseSize * 0.2
        let total = supportH + (context.isEmpty ? 0 : gap) + heroH
        var y = H * 0.5 - total / 2

        var out: [ShotWord] = []
        if !context.isEmpty {
            out += ctx.row(context, texts, size: supportSize, trackingAdd: track, align: .center(W / 2), y: y + supportH / 2, delayStart: 0)
            y += supportH + gap
        }
        out.append(ctx.word(texts[h], index: h, size: heroSize, center: CGPoint(x: W / 2, y: y + heroH / 2), delay: 0.06, emphasis: true))
        return out.sorted { $0.covers.lowerBound < $1.covers.lowerBound }
    }

    // MARK: - scatter

    private static func scatter(_ texts: [String], hero h: Int, seed: UInt64, ctx: ShotContext) -> [ShotWord] {
        let W = ctx.width, H = ctx.height
        var rng = SplitMix64(state: seed)

        // Phrases in reading order; the hero is always a phrase of its own. At most six in all,
        // one per grid cell.
        let pre = Array(0..<h), post = Array((h + 1)..<texts.count)
        var preChunks = 0, postChunks = 0
        let room = 5
        if !pre.isEmpty && !post.isEmpty {
            preChunks = min(pre.count, max(1, Int((Double(room) * Double(pre.count) / Double(pre.count + post.count)).rounded())))
            postChunks = min(post.count, room - preChunks)
            if postChunks == 0 { postChunks = 1; preChunks = min(preChunks, room - 1) }
        } else if !pre.isEmpty {
            preChunks = min(pre.count, room)
        } else {
            postChunks = min(post.count, room)
        }
        func split(_ indices: [Int], into k: Int) -> [[Int]] {
            guard k > 0, !indices.isEmpty else { return [] }
            return (0..<k).map { c in
                let lo = indices.count * c / k, hi = indices.count * (c + 1) / k
                return Array(indices[lo..<hi])
            }.filter { !$0.isEmpty }
        }
        let chunks: [(words: [Int], emphasis: Bool)] =
            split(pre, into: preChunks).map { ($0, false) } + [([h], true)] + split(post, into: postChunks).map { ($0, false) }

        // A 3 x 2 grid; chunks go to cells in a seeded order, nudged a little off-centre.
        let cols: [CGFloat] = [0.2, 0.5, 0.8], rows: [CGFloat] = [0.32, 0.68]
        var cells = (0..<6).map { (col: $0 % 3, row: $0 / 3) }
        for i in stride(from: cells.count - 1, to: 0, by: -1) { cells.swapAt(i, Int(rng.next() % UInt64(i + 1))) }

        var out: [ShotWord] = []
        for (k, chunk) in chunks.enumerated() {
            let text = chunk.words.map { texts[$0] }.joined(separator: " ")
            let cell = cells[k]
            // Each phrase is as big as its cell allows: short phrases large, long ones smaller, the
            // hero allowed to be bigger than the rest. Capped so one word never dwarfs the frame.
            let limit = Double(0.26 * W)
            let unit = ctx.unitWidth(text)
            let floor = chunk.emphasis ? ctx.baseSize * 1.2 : ctx.baseSize * 0.7
            let ceiling = chunk.emphasis ? ctx.baseSize * 3.2 : ctx.baseSize * 2.2
            var size = min(max(limit / unit, floor), ceiling, Double(0.22 * H))
            size = min(size, limit / unit)   // never wider than the cell, even below the floor
            let center = CGPoint(
                x: cols[cell.col] * W + CGFloat(rng.unit() - 0.5) * 0.04 * W,
                y: rows[cell.row] * H + CGFloat(rng.unit() - 0.5) * 0.06 * H)
            var word = ctx.word(text, index: chunk.words[0], size: size, center: center, delay: 0, emphasis: chunk.emphasis)
            word.covers = chunk.words[0]..<(chunk.words[chunk.words.count - 1] + 1)
            word.appearsWhenSung = true
            out.append(word)
        }
        return out
    }

    // MARK: - wall

    private static func wall(_ texts: [String], hero h: Int, ctx: ShotContext) -> [ShotWord] {
        let W = ctx.width, H = ctx.height
        let maxRow = Double(0.84 * W), maxBlock = Double(0.76 * H)
        let units = texts.map { ctx.unitWidth($0) }

        func wrap(_ size: Double) -> [[Int]] {
            var rows: [[Int]] = [[]]
            var used = 0.0
            for i in texts.indices {
                let w = units[i] * size
                let gap = 0.28 * size
                if !rows[rows.count - 1].isEmpty, used + gap + w > maxRow { rows.append([]); used = 0 }
                used += (rows[rows.count - 1].isEmpty ? 0 : gap) + w
                rows[rows.count - 1].append(i)
            }
            return rows
        }

        // The largest size whose wrapped block still fits the frame.
        var lo = 6.0, hi = min(maxRow / (units.max() ?? 1), Double(0.3 * H))
        if hi < lo { lo = hi }
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            if Double(wrap(mid).count) * ctx.lineHeightUnit * mid * 0.95 <= maxBlock { lo = mid } else { hi = mid }
        }
        let size = lo
        let rows = wrap(size)
        let rowH = CGFloat(ctx.lineHeightUnit * size * 0.95)
        var y = H / 2 - rowH * CGFloat(rows.count) / 2 + rowH / 2
        let left = (W - CGFloat(maxRow)) / 2

        var out: [ShotWord] = []
        for (r, row) in rows.enumerated() {
            let natural = row.reduce(0.0) { $0 + units[$1] * size } + Double(row.count - 1) * 0.28 * size
            let isLast = r == rows.count - 1
            // Justify every row but the last; a row that would need huge gaps stays centered instead.
            var gap = 0.28 * size
            var x = left
            if !isLast, row.count > 1, maxRow - natural <= 1.6 * 0.28 * size * Double(row.count - 1) {
                gap += (maxRow - natural) / Double(row.count - 1)
            } else if !isLast {
                x = (W - CGFloat(natural)) / 2
            }
            for i in row {
                let w = CGFloat(units[i] * size)
                out.append(ctx.word(texts[i], index: i, size: size, center: CGPoint(x: x + w / 2, y: y),
                                    delay: min(0.02 * Double(i), 0.15), emphasis: i == h))
                x += w + CGFloat(gap)
            }
            y += rowH
        }
        return out
    }
}

// MARK: - Measuring

/// Everything a template needs to turn words into placed items. Widths come from measuring once at
/// a reference size and scaling, which is exact for tracking given in em and keeps a frame's cost
/// to a handful of measurements however many sizes a template tries.
struct ShotContext {
    let viewport: CGSize
    let baseFont: FontSpec
    let measurer: TextMeasuring

    var width: CGFloat { viewport.width }
    var height: CGFloat { viewport.height }
    var baseSize: Double { baseFont.size }
    /// No word is settled wider than this, which leaves room for the camera's push-in.
    var maxWordWidth: CGFloat { 0.84 * viewport.width }

    private let reference = 100.0

    func font(size: Double, trackingAdd: Double = 0) -> FontSpec {
        FontSpec(family: baseFont.family, size: size, weight: baseFont.weight,
                 tracking: baseFont.tracking + trackingAdd, italic: baseFont.italic)
    }

    /// Width in points per point of font size.
    func unitWidth(_ text: String, trackingAdd: Double = 0) -> Double {
        max(0.0001, Double(measurer.width(of: text, font: font(size: reference, trackingAdd: trackingAdd))) / reference)
    }

    var lineHeightUnit: Double { Double(measurer.lineHeight(font: font(size: reference))) / reference }

    enum Alignment { case center(CGFloat), left(CGFloat), right(CGFloat) }

    /// A finished item: the width and height come from the real measurer at the real size.
    func word(_ text: String, index: Int, size: Double, center: CGPoint, delay: Double, emphasis: Bool, trackingAdd: Double = 0) -> ShotWord {
        let f = font(size: size, trackingAdd: trackingAdd)
        return ShotWord(text: text, font: f, width: measurer.width(of: text, font: f), height: measurer.lineHeight(font: f),
                        center: center, delay: delay, isEmphasis: emphasis, covers: index..<(index + 1), appearsWhenSung: false)
    }

    /// The gap between words, in points per point of font size. Wide letter-spacing needs a wider
    /// gap, or the words run together ("againandagain").
    static func gapUnits(trackingAdd: Double) -> Double { 0.28 + 1.6 * trackingAdd }

    /// The largest size up to `size` at which these words fit on one row of `maxWidth`.
    func fitRowSize(_ indices: [Int], _ texts: [String], size: Double, trackingAdd: Double, maxWidth: CGFloat) -> Double {
        let units = indices.map { unitWidth(texts[$0], trackingAdd: trackingAdd) }
        let gapUnits = Self.gapUnits(trackingAdd: trackingAdd) * Double(max(0, indices.count - 1))
        let perPoint = units.reduce(0, +) + gapUnits
        guard perPoint > 0 else { return size }
        return min(size, Double(maxWidth) / perPoint)
    }

    /// One row of words, in order, at one size.
    func row(_ indices: [Int], _ texts: [String], size: Double, trackingAdd: Double, align: Alignment, y: CGFloat,
             delayStart: Double) -> [ShotWord] {
        let widths = indices.map { CGFloat(unitWidth(texts[$0], trackingAdd: trackingAdd) * size) }
        let gap = CGFloat(Self.gapUnits(trackingAdd: trackingAdd) * size)
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, indices.count - 1))
        var x: CGFloat
        switch align {
        case .center(let c): x = c - total / 2
        case .left(let l): x = l
        case .right(let r): x = r - total
        }
        var out: [ShotWord] = []
        for (n, i) in indices.enumerated() {
            out.append(word(texts[i], index: i, size: size, center: CGPoint(x: x + widths[n] / 2, y: y),
                            delay: min(delayStart + 0.03 * Double(n), 0.15), emphasis: false, trackingAdd: trackingAdd))
            x += widths[n] + gap
        }
        return out
    }
}
