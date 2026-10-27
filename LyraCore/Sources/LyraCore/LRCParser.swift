import Foundation

/// Parses LRC lyrics, including repeated timestamps (`[00:10.00][01:30.00]text`),
/// the `[offset:ms]` tag and enhanced per-word tags (`<00:10.50>word`).
public enum LRCParser {
    private static let lineStampRegex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let wordStampRegex = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#)
    private static let tagRegex = try! NSRegularExpression(pattern: #"^\[([A-Za-z]+):(.*)\]$"#)

    private struct RawLine {
        var start: TimeInterval
        var text: String
        var words: [(time: TimeInterval, text: String)]
    }

    /// Returns nil when the text has no timestamped lines at all.
    public static func parse(_ text: String, trackDuration: TimeInterval? = nil, source: String = "lrc") -> LyricsDocument? {
        var offset: TimeInterval = 0
        var raw: [RawLine] = []

        for lineSub in text.split(whereSeparator: \.isNewline) {
            let line = lineSub.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }
            let (stamps, rest) = leadingStamps(in: line)
            if stamps.isEmpty {
                if let (key, value) = metadataTag(line), key.lowercased() == "offset", let ms = Double(value.trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                }
                continue
            }
            let (plain, words) = extractWords(from: rest)
            for t in stamps {
                raw.append(RawLine(start: t, text: plain, words: words))
            }
        }
        guard !raw.isEmpty else { return nil }

        // LRC offset: positive means lyrics should appear sooner.
        raw = raw.map { r in
            var r = r
            r.start = max(0, r.start - offset)
            r.words = r.words.map { ($0.time - offset, $0.text) }
            return r
        }
        raw.sort { $0.start < $1.start }

        var lines: [LyricLine] = []
        var anyRealWords = false
        for (i, r) in raw.enumerated() {
            let nextStart = i + 1 < raw.count ? raw[i + 1].start : nil
            let fallbackEnd = trackDuration.map { max($0, r.start + 1) } ?? (r.start + 5)
            let end = max(nextStart ?? fallbackEnd, r.start + 0.05)

            if r.text.isEmpty {
                lines.append(LyricLine(start: r.start, end: end, sungEnd: r.start, text: "", words: []))
                continue
            }

            let sungEnd = min(end, r.start + WordTiming.estimatedSungDuration(text: r.text) * 1.5)
            var words: [LyricWord]
            if r.words.isEmpty {
                words = WordTiming.interpolate(text: r.text, start: r.start, end: sungEnd)
            } else {
                anyRealWords = true
                words = realWords(r.words, lineEnd: end)
            }
            let lineSungEnd = words.last.map { min($0.end, end) } ?? sungEnd
            lines.append(LyricLine(start: r.start, end: end, sungEnd: lineSungEnd, text: r.text, words: words))
        }

        return LyricsDocument(lines: lines, isSynced: true, hasWordTiming: anyRealWords, source: source, plainText: nil)
    }

    // MARK: - Helpers

    private static func seconds(_ ns: NSString, _ m: NSTextCheckingResult) -> TimeInterval {
        let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
        let secs = Double(ns.substring(with: m.range(at: 2))) ?? 0
        var frac = 0.0
        if m.range(at: 3).location != NSNotFound {
            frac = Double("0." + ns.substring(with: m.range(at: 3))) ?? 0
        }
        return minutes * 60 + secs + frac
    }

    /// Consumes consecutive leading `[mm:ss.xx]` stamps.
    private static func leadingStamps(in line: String) -> ([TimeInterval], String) {
        let ns = line as NSString
        var pos = 0
        var stamps: [TimeInterval] = []
        while pos < ns.length,
              let m = lineStampRegex.firstMatch(in: line, options: [.anchored], range: NSRange(location: pos, length: ns.length - pos)) {
            stamps.append(seconds(ns, m))
            pos = m.range.location + m.range.length
        }
        return (stamps, ns.substring(from: pos).trimmingCharacters(in: .whitespaces))
    }

    private static func metadataTag(_ line: String) -> (String, String)? {
        let ns = line as NSString
        guard let m = tagRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }

    /// Splits text with enhanced `<mm:ss.xx>` tags into plain text plus timed pieces.
    private static func extractWords(from text: String) -> (String, [(time: TimeInterval, text: String)]) {
        let ns = text as NSString
        let matches = wordStampRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }

        var pieces: [(time: TimeInterval, text: String)] = []
        for (i, m) in matches.enumerated() {
            let from = m.range.location + m.range.length
            let to = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let piece = ns.substring(with: NSRange(location: from, length: to - from)).trimmingCharacters(in: .whitespaces)
            pieces.append((seconds(ns, m), piece))
        }
        let plain = pieces.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
        return (plain, pieces)
    }

    /// Builds words from timed pieces; an empty piece just marks the previous word's end.
    private static func realWords(_ pieces: [(time: TimeInterval, text: String)], lineEnd: TimeInterval) -> [LyricWord] {
        var words: [LyricWord] = []
        for (i, p) in pieces.enumerated() where !p.text.isEmpty {
            let end = i + 1 < pieces.count ? pieces[i + 1].time : lineEnd
            words.append(LyricWord(text: p.text, start: p.time, end: max(end, p.time + 0.05), isEstimated: false))
        }
        return words
    }
}
