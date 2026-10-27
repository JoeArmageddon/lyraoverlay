import Foundation

public enum PlayerKind: String, Codable, Sendable {
    case spotify
    case appleMusic
}

public struct Track: Equatable, Hashable, Codable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var player: PlayerKind
    /// Genre tag when the player exposes one (Apple Music does, Spotify doesn't). May be empty.
    public var genre: String
    /// Player-specific identifier, used to detect track changes. May be empty.
    public var id: String

    public init(title: String, artist: String, album: String, duration: TimeInterval, player: PlayerKind, genre: String = "", id: String = "") {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.player = player
        self.genre = genre
        self.id = id
    }
}

public struct PlaybackSnapshot: Equatable, Sendable {
    public var track: Track?
    public var position: TimeInterval
    public var isPlaying: Bool
    /// When `position` was valid. Consumers extrapolate from here.
    public var capturedAt: Date

    public init(track: Track?, position: TimeInterval, isPlaying: Bool, capturedAt: Date = Date()) {
        self.track = track
        self.position = position
        self.isPlaying = isPlaying
        self.capturedAt = capturedAt
    }

    public static let idle = PlaybackSnapshot(track: nil, position: 0, isPlaying: false)

    /// Playback position at `date`, extrapolated while playing.
    public func position(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return position }
        return position + max(0, date.timeIntervalSince(capturedAt))
    }
}

public struct LyricWord: Equatable, Codable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    /// False when the timing came from the lyrics source, true when interpolated.
    public var isEstimated: Bool

    public init(text: String, start: TimeInterval, end: TimeInterval, isEstimated: Bool) {
        self.text = text
        self.start = start
        self.end = end
        self.isEstimated = isEstimated
    }
}

public struct LyricLine: Equatable, Codable, Sendable {
    public var start: TimeInterval
    /// Start of the next line, or an estimate for the last one.
    public var end: TimeInterval
    /// When singing is expected to stop. At most `end`; the rest is a gap.
    public var sungEnd: TimeInterval
    public var text: String
    public var words: [LyricWord]

    public init(start: TimeInterval, end: TimeInterval, sungEnd: TimeInterval, text: String, words: [LyricWord]) {
        self.start = start
        self.end = end
        self.sungEnd = sungEnd
        self.text = text
        self.words = words
    }

    public var isInstrumentalGap: Bool { text.isEmpty }
}

public struct LyricsDocument: Equatable, Codable, Sendable {
    public var lines: [LyricLine]
    public var isSynced: Bool
    /// True when at least one line carries timing from the source, not interpolation.
    public var hasWordTiming: Bool
    public var source: String
    public var plainText: String?
    public var instrumental: Bool

    public init(lines: [LyricLine], isSynced: Bool, hasWordTiming: Bool, source: String, plainText: String? = nil, instrumental: Bool = false) {
        self.lines = lines
        self.isSynced = isSynced
        self.hasWordTiming = hasWordTiming
        self.source = source
        self.plainText = plainText
        self.instrumental = instrumental
    }
}
