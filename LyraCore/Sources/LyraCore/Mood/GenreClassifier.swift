import Foundation

/// A genre string mapped to a mood.
public struct GenreGuess: Equatable, Sendable {
    public var mood: Mood
    /// 0...1: how much a genre tag alone says about the feel of a song.
    public var confidence: Double
    /// The rules that fired (normalized keywords), for diagnostics.
    public var matched: [String]
}

/// Maps free-form genre tags ("Hip-Hop/Rap", "R&B/Soul", "Música Clásica", "Rock, Alternative") to a
/// mood. Table driven: each rule is a keyword (one or more words; a trailing `*` matches any word that
/// starts with it) with a mood and a confidence. Within one genre segment the most specific rule wins
/// (more words, then longer text, then higher confidence), so "doom metal" beats "metal".
public enum GenreClassifier {
    struct Rule: Sendable {
        let words: [String]
        let prefix: Bool
        let mood: Mood
        let weight: Double
        let text: String
    }

    // MARK: Table

    /// Confidences express how reliably the keyword implies the mood, not how popular the genre is:
    /// "lo-fi" is nearly always chill (0.9); "pop" could be anything (0.35).
    private static let table: [(Mood, Double, [String])] = [
        (.aggressive, 0.92, ["metal", "heavy metal", "thrash*", "death metal", "metalcore", "deathcore", "grindcore", "hardcore", "nu metal", "djent", "screamo"]),
        (.aggressive, 0.7, ["punk", "hard rock", "industrial", "gangsta rap", "gangster rap", "grime", "drill", "uk drill", "horrorcore", "hardstyle", "gabber", "crossover"]),
        (.aggressive, 0.55, ["trap", "mosh", "riot*"]),
        (.dark, 0.88, ["goth*", "darkwave", "dark ambient", "dark wave", "doom*", "black metal", "doom metal", "witch house", "dark electro", "ebm", "neofolk", "death rock", "deathrock", "coldwave", "darksynth"]),
        (.dark, 0.7, ["trip hop", "triphop", "phonk", "horror", "post punk", "dark*", "grunge", "occult", "noir", "drone"]),
        (.dark, 0.5, ["idm", "experimental"]),
        (.epic, 0.85, ["orchestral", "symphonic", "symphonic metal", "power metal", "epic*", "film score", "cinematic", "trailer", "opera*", "symphony*", "score"]),
        (.epic, 0.65, ["soundtrack*", "original score", "motion picture", "prog rock", "progressive rock", "progressive metal", "post rock", "post-rock", "gregorian", "choral", "baroque", "orchestra"]),
        (.epic, 0.5, ["classical", "klassik", "klassisk", "clasica", "classique", "classica", "klassiek", "gospel", "worship", "anthem*", "sinfonia", "progressive", "stadium"]),
        (.party, 0.85, ["dance", "edm", "house", "club", "dancehall", "reggaeton", "eurodance", "disco", "deep house", "tech house", "electro house", "big room", "dance pop", "tanz", "baile", "bubblegum bass", "moombahton", "hi nrg", "bounce"]),
        (.party, 0.75, ["techno", "trance", "salsa", "merengue", "samba", "cumbia", "afrobeat*", "afrobeats", "amapiano", "soca", "bhangra", "funk carioca", "baile funk", "latin pop", "urbano", "reggaeton", "latin urban", "kuduro", "zouk", "axe", "forro", "pagode", "hyphy", "party*"]),
        (.party, 0.55, ["latin", "latino", "k pop", "kpop", "funk", "dembow", "twerk", "reggaetón", "latina", "tropical", "electronic dance", "turbo folk", "chalga", "schlager"]),
        (.energetic, 0.8, ["drum and bass", "drum n bass", "dnb", "jungle", "dubstep", "electro", "breakbeat", "big beat", "pop punk", "skate punk", "power pop", "punk pop", "rap rock", "garage rock", "stoner rock", "hard dance", "happy hardcore", "speedcore", "psytrance", "psy trance", "neurofunk"]),
        (.energetic, 0.55, ["hip hop", "hiphop", "rap", "hip hop rap", "rap hip hop", "pop rock"]),
        (.energetic, 0.45, ["electronic*"]),
        (.energetic, 0.6, ["indie rock", "rock and roll", "rock n roll", "alt rock", "alternative rock", "arena rock", "britpop", "rock*", "electronica rock", "crunk", "southern rap", "boom bap", "uk rap", "deutschrap", "french rap", "rap francais", "rap fr", "dutch rap", "sport*", "workout", "fitness", "running", "gym"]),
        (.retro, 0.85, ["synthwave", "retrowave", "outrun", "vaporwave", "city pop", "oldies", "doo wop", "rockabilly", "italo disco", "retro*", "nostalg*", "80s", "70s", "60s", "50s", "90s", "eighties", "seventies", "sixties"]),
        (.retro, 0.7, ["new wave", "synthpop", "synth pop", "synth*", "big band", "swing", "classic rock", "motown", "surf*", "easy listening oldies", "vintage*", "classic pop", "golden oldies", "northern soul", "bubblegum pop", "glam rock", "eurobeat", "chiptune retro", "8 bit", "bit pop", "music hall", "ragtime", "dixieland", "charleston"]),
        (.retro, 0.55, ["standards", "traditional pop", "vocal pop", "tin pan alley", "american popular song", "glam", "disco funk"]),
        (.dreamy, 0.88, ["dream pop", "shoegaze", "dreampop", "ethereal*", "dreamy", "chillwave", "slowdive", "hypnagogic*", "psychedelic*", "psych pop", "psych rock", "psychedelic rock", "space rock", "cosmic*", "neoclassical", "neo classical", "ambient pop", "cloud rap", "glitch pop", "hyperpop dream", "bedroom pop"]),
        (.dreamy, 0.72, ["ambient", "new age", "indietronica", "art pop", "chamber pop", "downtempo dream", "post rock dream", "balearic", "celestial", "sound healing", "meditative"]),
        (.chill, 0.9, ["lofi hip hop", "lo fi hip hop", "chillhop", "jazz hop", "lo fi", "lofi", "chillout", "chill*", "relax*", "sleep", "spa", "meditation", "yoga", "nature sounds", "lounge", "bossa nova", "downtempo", "calm*", "healing", "white noise"]),
        (.chill, 0.72, ["smooth jazz", "reggae", "dub", "yacht rock", "neo soul", "nu jazz", "acid jazz", "easy listening", "bossa*", "tropical house", "reggae fusion", "roots reggae", "lovers rock", "world fusion", "hawaiian", "island", "beach", "surf rock chill", "electronica"]),
        (.dreamy, 0.5, ["indie"]),
        (.chill, 0.55, ["jazz", "jazz fusion", "latin jazz", "cool jazz", "soft jazz"]),
        (.chill, 0.5, ["bebop", "easy", "adult alternative"]),
        (.romantic, 0.9, ["love song*", "romantic*", "romance", "quiet storm", "bolero", "wedding", "serenade", "chanson romantique", "slow jam*", "slow dance", "sensual*"]),
        (.romantic, 0.75, ["ballad*", "tango", "r and b", "rnb", "r b", "rhythm and blues", "vocal jazz", "crooner*", "torch song*", "balada*", "soft rock", "adult contemporary", "ranchera", "flamenco", "bachata", "mpb", "chanson", "canzone", "cantautor*", "bossa nova romantic", "contemporary r and b", "contemporary rnb", "alternative r and b", "alt r and b", "pop ballad"]),
        (.romantic, 0.55, ["soul", "soul and r and b", "contemporary soul", "vocal standards", "easy pop", "sophisti pop", "classic soul", "gospel soul", "southern soul", "blue eyed soul"]),
        (.melancholic, 0.88, ["sad*", "melanchol*", "slowcore", "sadcore", "emo", "fado", "blues", "delta blues", "chicago blues", "blues rock slow", "depressive*", "weltschmerz", "heartbreak*", "breakup", "emo rap", "midwest emo", "tristeza", "triste", "nocturne*", "lament*", "elegy", "requiem", "dirge"]),
        (.melancholic, 0.6, ["enka", "torch*", "country blues", "piano ballad", "post hardcore melodic", "indie folk sad", "minimal piano", "solo piano", "lullaby*", "string quartet", "chamber music", "etude*", "romantic classical"]),
        (.acoustic, 0.9, ["acoustic*", "unplugged", "singer songwriter", "singer", "songwriter", "folk", "bluegrass", "americana", "indie folk", "folk rock", "country folk", "celtic", "irish*", "roots*", "old time", "appalachian", "campfire", "busking", "troubadour", "cantautor", "liedermacher", "trad*", "traditional", "traditional folk", "worldbeat acoustic", "mountain music", "hillbilly", "string band", "fingerstyle", "classical guitar", "flamenco guitar", "ukulele", "banjo", "mandolin", "harp", "zither", "didgeridoo", "nordic folk", "scandinavian folk", "chanson folk"]),
        (.acoustic, 0.6, ["country*", "western", "honky tonk", "outlaw country", "alt country", "alternative country", "cowboy", "mariachi", "norteno", "norteño", "tejano", "ranchero", "volksmusik", "polka", "waltz", "klezmer", "gypsy", "balkan", "bluegrass gospel", "christian folk", "christian", "ccm", "contemporary christian", "inspirational", "spiritual*", "devotional", "hymn*", "world acoustic"]),
        (.playful, 0.88, ["kids", "children*", "childrens", "kinder*", "enfant*", "nursery*", "novelty", "comedy", "humor*", "parody", "disney", "cartoon", "ska", "ska punk", "third wave ska", "two tone", "chiptune", "j pop", "jpop", "anime", "kawaii", "bubblegum*", "happy", "holiday*", "christmas", "xmas", "weihnacht*", "navidad", "noel", "vocaloid", "video game", "game music", "bossa kids", "singalong", "sing along", "cheerful"]),
        (.melancholic, 0.45, ["piano*", "cello", "violin", "chamber"]),
        (.melancholic, 0.35, ["alternative", "alt", "alternativo", "alternatif"]),
        (.aggressive, 0.6, ["rage"]),
        (.playful, 0.4, ["pop", "pop*"]),
        (.playful, 0.5, ["teen pop", "bubblegum pop playful", "bollywood", "filmi", "tollywood", "kollywood", "cantopop", "mandopop", "c pop", "t pop", "v pop", "top 40", "mainstream", "chart*", "pop latino", "latin pop playful", "europop", "pop dance playful", "musical*", "show tunes", "broadway", "cast recording", "musical theatre", "musical theater", "stage and screen", "vaudeville", "cabaret"]),
    ]

    // Words that carry no genre information.
    private static let generic: Set<String> = [
        "music", "musik", "musica", "musique", "genres", "genre", "other", "others", "unknown", "unclassifiable",
        "various", "misc", "miscellaneous", "none", "n a", "na", "undefined", "unspecified", "mixed", "uncategorized", "uncategorised"
    ]

    private static let rules: [Rule] = {
        var all: [Rule] = []
        for (mood, weight, keywords) in table {
            for k in keywords {
                let prefix = k.hasSuffix("*")
                let text = normalize(prefix ? String(k.dropLast()) : k)
                let words = text.split(separator: " ").map(String.init)
                guard !words.isEmpty else { continue }
                all.append(Rule(words: words, prefix: prefix, mood: mood, weight: weight, text: text))
            }
        }
        return all
    }()

    /// Rule count, for tests.
    static var ruleCount: Int { rules.count }

    // MARK: Matching

    /// Lowercased, diacritics folded, "&" read as "and", punctuation collapsed to single spaces.
    /// "Hip-Hop/Rap" -> "hip hop rap", "Música Clásica" -> "musica clasica".
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
        var out = ""
        var lastSpace = true
        for ch in folded {
            if ch.isLetter || ch.isNumber { out.append(ch); lastSpace = false }
            else if !lastSpace { out.append(" "); lastSpace = true }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Splits a tag such as "Rock, Alternative / Indie" into its parts. A part that normalizes to
    /// nothing is dropped.
    static func segments(of genre: String) -> [String] {
        genre.split(whereSeparator: { "/,;|\u{FF0F}\u{3001}\u{FF0C}\n".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !normalize($0).isEmpty }
    }

    /// The most specific rule matching the given normalized words.
    private static func bestRule(for words: [String]) -> Rule? {
        var best: Rule?
        for rule in rules where matches(rule, words) {
            guard let b = best else { best = rule; continue }
            if (rule.words.count, rule.text.count, rule.weight) > (b.words.count, b.text.count, b.weight) { best = rule }
        }
        return best
    }

    private static func matches(_ rule: Rule, _ words: [String]) -> Bool {
        let n = rule.words.count
        guard words.count >= n else { return false }
        for start in 0...(words.count - n) {
            var ok = true
            for i in 0..<n {
                let w = words[start + i]
                let isLast = i == n - 1
                if !(w == rule.words[i] || (rule.prefix && isLast && w.hasPrefix(rule.words[i]))) { ok = false; break }
            }
            if ok { return true }
        }
        return false
    }

    /// The mood a genre tag points to, or nil when it says nothing (empty, "Music", unknown words).
    public static func classify(_ genre: String) -> GenreGuess? {
        let parts = segments(of: genre)
        guard !parts.isEmpty else { return nil }

        // The whole tag first ("Singer/Songwriter", "Hip-Hop/Rap" are single genres), then the parts.
        var votes: [Mood: Double] = [:]
        var best: [Mood: Double] = [:]
        var matched: [String] = []

        func vote(_ rule: Rule, weight segWeight: Double) {
            votes[rule.mood, default: 0] += rule.weight * segWeight
            best[rule.mood] = max(best[rule.mood] ?? 0, rule.weight)
            matched.append(rule.text)
        }

        let whole = normalize(parts.joined(separator: " "))
        let wholeWords = whole.split(separator: " ").map(String.init).filter { !generic.contains($0) }
        if parts.count > 1, let r = bestRule(for: wholeWords), r.words.count > 1 {
            // A multi-word rule spanning the separator ("hip hop rap", "singer songwriter").
            vote(r, weight: 1)
        } else {
            for (i, part) in parts.enumerated() {
                let words = normalize(part).split(separator: " ").map(String.init).filter { !generic.contains($0) }
                guard !words.isEmpty, let r = bestRule(for: words) else { continue }
                vote(r, weight: i == 0 ? 1 : 0.8)   // the first listed genre is the primary one
            }
        }
        guard let winner = votes.max(by: { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) }) else { return nil }
        let total = votes.values.reduce(0, +)
        let share = total > 0 ? winner.value / total : 1
        // A lone genre keeps its rule confidence; a mixed tag loses some for disagreeing with itself.
        let confidence = min(0.95, (best[winner.key] ?? 0) * (0.65 + 0.35 * share))
        return GenreGuess(mood: winner.key, confidence: confidence, matched: matched)
    }
}
