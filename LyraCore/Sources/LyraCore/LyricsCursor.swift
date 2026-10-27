import Foundation

public struct CursorState: Equatable, Sendable {
    /// Index of the current line, or nil before the first line starts.
    public var lineIndex: Int?
    /// Index of the word being sung, or nil if between words or in a gap.
    public var wordIndex: Int?
    /// 0...1 progress through the line's sung span.
    public var lineProgress: Double
    /// 0...1 progress through the current word (1 for words already sung).
    public var wordProgress: Double
    /// False in instrumental gaps and after a line's sung span has ended.
    public var isSinging: Bool

    public static let before = CursorState(lineIndex: nil, wordIndex: nil, lineProgress: 0, wordProgress: 0, isSinging: false)
}

/// Maps a playback position to the current line and word of a synced document.
public struct LyricsCursor: Sendable {
    public let lines: [LyricLine]

    public init(document: LyricsDocument) {
        self.lines = document.lines
    }

    public func state(at position: TimeInterval) -> CursorState {
        guard let i = lineIndex(at: position) else { return .before }
        let line = lines[i]
        let sungSpan = max(0.001, line.sungEnd - line.start)
        let lineProgress = min(1, max(0, (position - line.start) / sungSpan))
        let singing = !line.isInstrumentalGap && position < line.sungEnd

        var wordIndex: Int?
        var wordProgress = 0.0
        if singing, !line.words.isEmpty {
            // Last word that has started.
            var lo = 0, hi = line.words.count - 1, found = 0
            while lo <= hi {
                let mid = (lo + hi) / 2
                if line.words[mid].start <= position { found = mid; lo = mid + 1 } else { hi = mid - 1 }
            }
            wordIndex = found
            let w = line.words[found]
            wordProgress = min(1, max(0, (position - w.start) / max(0.001, w.end - w.start)))
        }
        return CursorState(lineIndex: i, wordIndex: wordIndex, lineProgress: lineProgress, wordProgress: wordProgress, isSinging: singing)
    }

    /// Binary search for the last line whose start is at or before `position`.
    func lineIndex(at position: TimeInterval) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= position { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}
