import Foundation

/// Estimates when each word in a line is sung when the source only has line timing.
public enum WordTiming {
    /// Rough sung duration for a line, used to cap lines followed by long gaps.
    public static func estimatedSungDuration(text: String) -> TimeInterval {
        Double(text.count) * 0.085 + 0.6
    }

    /// Splits `text` into words and spreads `start...end` across them by
    /// syllable count, with a small pause after punctuation.
    public static func interpolate(text: String, start: TimeInterval, end: TimeInterval) -> [LyricWord] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }
        let span = max(0.05, end - start)

        let weights = tokens.map(weight(of:))
        let total = weights.reduce(0, +)
        var cursor = start
        var words: [LyricWord] = []
        for (token, w) in zip(tokens, weights) {
            let dur = span * (w / total)
            words.append(LyricWord(text: token, start: cursor, end: cursor + dur, isEstimated: true))
            cursor += dur
        }
        return words
    }

    // MARK: - Tokenizing

    /// Whitespace-separated words; CJK and Hangul characters become one token each.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flush()
            } else if isCJK(scalar) {
                flush()
                tokens.append(String(scalar))
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        flush()
        return tokens
    }

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF: return true
        default: return false
        }
    }

    // MARK: - Weighting

    private static func weight(of token: String) -> Double {
        var w: Double
        if let first = token.unicodeScalars.first, isCJK(first) {
            w = 1
        } else {
            w = Double(syllables(in: token))
        }
        switch token.last {
        case ",", ";", ":", "—", "–": w += 0.3
        case ".", "!", "?", "…": w += 0.6
        default: break
        }
        return w
    }

    /// Vowel-group syllable estimate. Good enough for timing, not for poetry.
    static func syllables(in word: String) -> Int {
        let letters = word.lowercased().filter { $0.isLetter }
        guard !letters.isEmpty else { return 1 }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var inGroup = false
        for ch in letters {
            if vowels.contains(ch) {
                if !inGroup { count += 1 }
                inGroup = true
            } else {
                inGroup = false
            }
        }
        // Silent trailing "e" ("love", "time") but not "-le" ("little").
        if count > 1, letters.hasSuffix("e"), !letters.hasSuffix("le") { count -= 1 }
        return max(1, count)
    }
}
