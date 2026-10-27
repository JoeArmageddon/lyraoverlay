import Foundation

/// User choices for song-aware theming. Opt-in: it restyles the whole app, so it starts off.
public struct AutoThemeSettings: Equatable, Codable, Sendable {
    public var enabled = false
    /// Use the track's genre tag (Apple Music provides one, Spotify does not).
    public var useGenre = true
    /// Use the live audio analysis (needs audio permission; without it only genre and cover count).
    public var useAudio = true
    /// Use the colors of the cover art.
    public var useCover = true
    /// `Mood.rawValue` -> theme id: the user's own pick for a mood. Ids that don't exist are ignored.
    public var moodThemeIDs: [String: String] = [:]
    /// When non-empty, automatic changes only use these themes (the user's favorites).
    public var onlyThemeIDs: [String] = []

    public init() {}

    /// Tolerant: a missing or malformed field keeps its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.get(.enabled, enabled)
        useGenre = c.get(.useGenre, useGenre)
        useAudio = c.get(.useAudio, useAudio)
        useCover = c.get(.useCover, useCover)
        moodThemeIDs = c.get(.moodThemeIDs, moodThemeIDs)
        onlyThemeIDs = c.get(.onlyThemeIDs, onlyThemeIDs)
    }

    /// True when at least one signal is switched on.
    public var usesAnySignal: Bool { useGenre || useAudio || useCover }
}
