import Foundation

/// Combines the three things Lyra can know about a song into one `MoodGuess`.
///
/// Weights (how much each source may speak for the mood), applied to evidence the source produced:
///
///   genre tag      0.55   strongest: someone labelled the song, but tags can be coarse ("Pop")
///   audio profile  0.30   next: measured from the actual sound, but only once ~12 s have been heard
///                         and the analyzer normalizes loudness per song, so it is relative
///   cover palette  0.15   last: art colors hint at feel, but plenty of covers are unrelated to the sound
///
/// Each source turns its input into per-mood evidence, each value at most the source's own reliability
/// (a genre rule carries 0.35...0.92, audio at most 0.8, cover at most 0.6). A source's say is its
/// weight times its strongest evidence ("sureness"); the result is the say-weighted average of the
/// evidence, so a missing or empty source neither helps nor drags the result down, one source alone
/// keeps its own numbers, and a vague source (genre "Pop", a grey cover) yields to a clear one.
/// The winner's score is finally discounted a little when a runner-up is close. Any subset of sources works; with none, or with only
/// evidence too thin to matter, the answer is `.neutral` with confidence 0.
public struct MoodEngine: Sendable {
    public struct Weights: Equatable, Sendable {
        public var genre = 0.55
        public var audio = 0.30
        public var cover = 0.15
        public init() {}
    }

    public var weights = Weights()
    /// A normalized top score below this is "nothing stands out".
    public var neutralBelow = 0.12

    public init() {}

    public func guess(genre: String? = nil, audio: AudioSummary? = nil, palette: Palette? = nil) -> MoodGuess {
        var total: [Mood: Double] = [:]
        var weightSum = 0.0
        var reasons: [(Double, String)] = []

        // A source's say is its weight times how sure it is of itself (the strongest evidence it
        // produced), so a vague genre like "Pop" yields to clear audio while "Heavy Metal" does not.
        func add(_ dist: [Mood: Double], weight: Double, reason: String) {
            let sureness = dist.values.max() ?? 0
            guard sureness > 0 else { reasons.append((weight, reason)); return }
            let say = weight * sureness
            for (m, v) in dist { total[m, default: 0] += v * say }
            weightSum += say
            reasons.append((weight, reason))
        }

        if let genre, let g = GenreClassifier.classify(genre) {
            add([g.mood: g.confidence], weight: weights.genre,
                reason: "genre \u{201C}\(Self.displayGenre(genre))\u{201D} suggests \(g.mood.title)")
        }
        if let audio {
            let d = Self.audioEvidence(audio)
            let top = d.max { $0.value < $1.value }
            add(d, weight: weights.audio,
                reason: "audio is \(Self.describe(audio))" + (top.map { $0.value > 0.1 ? ", leaning \($0.key.title)" : "" } ?? ""))
        }
        if let palette {
            let d = Self.coverEvidence(palette)
            add(d, weight: weights.cover, reason: "cover is \(Self.describe(palette))")
        }

        guard weightSum > 0 else { return .neutral }
        var scores: [Mood: Double] = [:]
        for (m, v) in total { scores[m] = v / weightSum }

        let ranked = scores.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
        guard let first = ranked.first, first.value >= neutralBelow else {
            return MoodGuess(mood: .neutral, confidence: 0, reasons: reasons.map(\.1) + ["no clear mood"], scores: scores)
        }
        let second = ranked.count > 1 ? ranked[1].value : 0
        let margin = (first.value - second) / first.value
        let confidence = min(1, first.value * (0.75 + 0.25 * margin))
        return MoodGuess(mood: first.key, confidence: confidence, reasons: reasons.map(\.1), scores: scores)
    }

    // MARK: - Audio

    private static func ramp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        let t = min(1, max(0, (x - lo) / (hi - lo)))
        return t * t * (3 - 2 * t)
    }

    /// Fuzzy rules over tempo, fullness, brightness, bass and dynamics. Every rule is a product of
    /// 0...1 memberships, scaled to at most 0.8. A missing tempo counts as "unsure" (0.35) for every
    /// tempo-based membership, which keeps tempo-dependent moods weak instead of absent.
    static func audioEvidence(_ a: AudioSummary) -> [Mood: Double] {
        let t = a.tempo
        let fast = t.map { ramp($0, 105, 140) } ?? 0.35
        let veryFast = t.map { ramp($0, 140, 170) } ?? 0.2
        let slow = t.map { 1 - ramp($0, 70, 100) } ?? 0.35
        let slowish = t.map { 1 - ramp($0, 85, 115) } ?? 0.4
        let danceT = t.map { ramp($0, 95, 112) * (1 - ramp($0, 145, 165)) } ?? 0.3
        let upbeat = t.map { ramp($0, 100, 125) } ?? 0.3
        let heavyTempo = t.map { ramp($0, 85, 120) } ?? 0.4

        let loud = ramp(a.energy, 0.35, 0.6)
        let quiet = 1 - ramp(a.energy, 0.25, 0.45)
        let bright = ramp(a.brightness, 0.4, 0.65)
        let dark = 1 - ramp(a.brightness, 0.25, 0.45)
        let midBright = 1 - ramp(abs(a.brightness - 0.45), 0.1, 0.3)
        let bassy = ramp(a.bassShare, 0.38, 0.5)
        let dyn = ramp(a.dynamics, 0.3, 0.6)
        let steady = 1 - ramp(a.dynamics, 0.2, 0.4)

        var e: [Mood: Double] = [:]
        e[.energetic] = fast * loud * (0.6 + 0.4 * bright)
        e[.party] = danceT * loud * (0.6 + 0.4 * bassy) * (0.7 + 0.3 * bright)
        e[.aggressive] = loud * dark * (0.4 + 0.6 * heavyTempo) * (0.5 + 0.5 * bassy)
        e[.dark] = dark * bassy * (1 - 0.5 * loud)
        e[.melancholic] = slow * quiet * dark
        e[.chill] = slowish * (1 - ramp(a.energy, 0.3, 0.55)) * (0.5 + 0.5 * steady) * (1 - 0.5 * dark)
        e[.dreamy] = quiet * steady * bright * (0.5 + 0.5 * slow)
        e[.romantic] = slow * quiet * midBright * 0.8
        e[.acoustic] = quiet * dyn * (1 - bassy) * 0.9
        e[.epic] = loud * dyn * (1 - 0.5 * veryFast)
        e[.playful] = upbeat * bright * (0.5 + 0.5 * loud) * 0.6
        return e.mapValues { min(0.8, $0 * 0.8) }
    }

    static func describe(_ a: AudioSummary) -> String {
        var parts: [String] = []
        if let t = a.tempo { parts.append(t >= 125 ? "fast (\(Int(t.rounded())) BPM)" : t <= 85 ? "slow (\(Int(t.rounded())) BPM)" : "mid-tempo (\(Int(t.rounded())) BPM)") }
        parts.append(a.energy >= 0.55 ? "loud" : a.energy <= 0.3 ? "quiet" : "moderate")
        parts.append(a.brightness >= 0.55 ? "bright" : a.brightness <= 0.3 ? "dark" : "warm")
        if a.bassShare >= 0.45 { parts.append("bass-heavy") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Cover

    struct HSV { var h: Double; var s: Double; var v: Double }

    static func hsv(_ c: RGBA) -> HSV {
        let r = Double(c.r), g = Double(c.g), b = Double(c.b)
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return HSV(h: h, s: mx > 0 ? d / mx : 0, v: mx)
    }

    /// Cover evidence, at most 0.6 in total: dark and muted art leans dark or melancholic, vivid warm art
    /// leans playful or romantic (reds and pinks more romantic), cool art leans chill or dreamy
    /// (violet more dreamy), pale or green art leans acoustic.
    static func coverEvidence(_ p: Palette) -> [Mood: Double] {
        let dom = hsv(p.dominant)
        let acc = hsv(p.accent)
        let luma = ColorMath.luma(p.dominant)
        var e: [Mood: Double] = [:]
        func add(_ m: Mood, _ v: Double) { e[m, default: 0] += v }

        let dark = p.isDark ? 1.0 : 0.0
        let veryDark = 1 - ramp(luma, 0.1, 0.35)
        let muted = 1 - ramp(max(dom.s, acc.s * 0.6), 0.25, 0.6)
        let vivid = ramp(acc.s, 0.45, 0.8) * ramp(acc.v, 0.5, 0.8)
        let hue = acc.h

        // Dark art.
        add(.dark, 0.3 * max(dark * muted, veryDark * 0.7))
        add(.melancholic, 0.2 * dark * muted)
        add(.aggressive, 0.15 * dark * vivid * (hue < 20 || hue > 340 ? 1 : 0))
        // Warm and vivid.
        let warm = (hue < 70 || hue > 330) ? 1.0 : 0.0
        let pinkRed = (hue < 20 || hue > 290) ? 1.0 : 0.0
        add(.playful, 0.3 * vivid * warm * (1 - dark) * (1 - 0.5 * pinkRed))
        add(.romantic, 0.3 * vivid * pinkRed * (1 - 0.5 * dark))
        // Cool.
        let cool = (hue >= 170 && hue < 260) ? 1.0 : 0.0
        let violet = (hue >= 255 && hue <= 300) ? 1.0 : 0.0
        add(.chill, 0.3 * ramp(acc.s, 0.25, 0.6) * cool)
        add(.dreamy, 0.2 * ramp(acc.s, 0.25, 0.6) * (cool * 0.6 + violet))
        // Pale or earthy.
        let green = (hue >= 70 && hue < 170) ? 1.0 : 0.0
        add(.acoustic, 0.3 * ramp(acc.s, 0.25, 0.6) * green)
        add(.acoustic, 0.2 * (1 - dark) * muted * ramp(luma, 0.5, 0.8))

        // Never claim more than 0.6 in total.
        e = e.mapValues { $0 * 1.3 }
        let sum = e.values.reduce(0, +)
        if sum > 0.6 { e = e.mapValues { $0 * 0.6 / sum } }
        return e
    }

    static func describe(_ p: Palette) -> String {
        let a = hsv(p.accent)
        let mood = p.isDark ? "dark" : "light"
        guard a.s > 0.3 else { return "\(mood) muted" }
        let hue: String
        switch a.h {
        case ..<20, 330...: hue = "red"
        case ..<70: hue = "warm"
        case ..<170: hue = "green"
        case ..<260: hue = "cool"
        default: hue = "purple"
        }
        return "\(mood) \(hue)"
    }

    static func displayGenre(_ g: String) -> String {
        let t = g.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 40 ? String(t.prefix(40)) + "…" : t
    }
}
