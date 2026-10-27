import Foundation

/// How lyric text is capitalized when drawn. The stored lyrics are never changed.
public enum TextCase: String, Codable, CaseIterable, Sendable {
    case asWritten
    case upper
    case lower
    case title

    public var title: String {
        switch self {
        case .asWritten: return "As Written"
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .title: return "Title Case"
        }
    }

    /// Locale-independent: the same lyrics look the same on every Mac.
    public func apply(_ s: String) -> String {
        switch self {
        case .asWritten: return s
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .title: return Self.titleCased(s)
        }
    }

    /// Capitalizes the first letter of each word and lowercases the rest. Leading
    /// punctuation is skipped ("(hello" becomes "(Hello") and digits end the word start ("3am" stays "3am").
    private static func titleCased(_ s: String) -> String {
        var out = ""
        var atWordStart = true
        for ch in s {
            if ch.isWhitespace {
                atWordStart = true
                out.append(ch)
            } else if ch.isLetter {
                out += atWordStart ? ch.uppercased() : ch.lowercased()
                atWordStart = false
            } else {
                if ch.isNumber { atWordStart = false }
                out.append(ch)
            }
        }
        return out
    }
}

extension LyricsDocument {
    /// A copy with every line and word re-cased. Timings, flags and `plainText` are untouched.
    public func applying(_ textCase: TextCase) -> LyricsDocument {
        guard textCase != .asWritten else { return self }
        var copy = self
        copy.lines = lines.map { line in
            var line = line
            line.text = textCase.apply(line.text)
            line.words = line.words.map { word in
                var word = word
                word.text = textCase.apply(word.text)
                return word
            }
            return line
        }
        return copy
    }
}
