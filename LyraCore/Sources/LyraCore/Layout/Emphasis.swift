import Foundation

/// Picks the one word of a line a cinematic shot is built around: the hero.
///
/// The choice is a score: longer content words win, words that end a clause or a sentence get a
/// boost, ALL CAPS words and the last word of the line get a nudge, and common function words
/// ("the", "and", "you") are heavily discouraged. Ties go to the later word, which is usually the
/// one the line lands on.
public enum EmphasisPicker {
    /// Index of the hero word in `words`, or 0 when `words` is empty.
    public static func index(of words: [String]) -> Int {
        guard words.count > 1 else { return 0 }

        // Unspaced scripts (Chinese, Japanese, Korean) arrive as one token per character with no
        // stop words to skip and no length to compare, so the middle of the line stands in.
        let tokens = words.filter { !core(of: $0).isEmpty }
        if tokens.count > 1, tokens.allSatisfy({ $0.unicodeScalars.allSatisfy(WordTiming.isCJK) }) {
            return words.count / 2
        }

        var best = 0
        var bestScore = -Double.infinity
        for (i, word) in words.enumerated() {
            let s = score(word, isLast: i == words.count - 1)
            if s >= bestScore {   // ">=": ties go to the later word
                bestScore = s
                best = i
            }
        }
        return best
    }

    // MARK: - Scoring

    static func score(_ word: String, isLast: Bool) -> Double {
        let core = core(of: word)
        guard !core.isEmpty else { return -100 }   // punctuation on its own is never the hero

        var s = Double(min(core.count, 12))
        if stopWords.contains(core.lowercased()) { s -= 50 }

        switch word.last {
        case "!", "?": s += 4
        case ".": s += 3
        case ",", ";", ":", "…": s += 2
        default: break
        }
        // ALL CAPS, but not a lone "I" or "A".
        if core.count >= 2, core.allSatisfy({ $0.isUppercase }) { s += 3 }
        if isLast { s += 2 }
        return s
    }

    /// Letters and digits only: "don't," becomes "dont".
    static func core(of word: String) -> String {
        String(word.filter { $0.isLetter || $0.isNumber })
    }

    /// Common English function words. Apostrophes are dropped before lookup, so "don't" is "dont".
    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "nor", "so", "yet", "for", "of", "to", "in", "on", "at", "by",
        "with", "from", "into", "onto", "up", "down", "out", "off", "over", "under", "as", "than", "that",
        "this", "these", "those", "it", "its", "itll", "is", "am", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "can", "could", "shall", "should", "may",
        "might", "must", "i", "me", "my", "mine", "we", "us", "our", "ours", "you", "your", "yours", "he",
        "him", "his", "she", "her", "hers", "they", "them", "their", "theirs", "im", "ive", "id", "ill",
        "youre", "youve", "youll", "youd", "hes", "shes", "were", "theyre", "theyve", "thats", "theres",
        "dont", "doesnt", "didnt", "cant", "couldnt", "wont", "wouldnt", "isnt", "arent", "wasnt", "werent",
        "if", "then", "when", "while", "just", "not", "no", "oh", "ooh", "yeah", "uh", "ah", "na", "la",
        "all", "any", "some", "there", "here", "what", "who", "how", "gonna", "wanna", "gotta", "get", "got",
    ]
}
