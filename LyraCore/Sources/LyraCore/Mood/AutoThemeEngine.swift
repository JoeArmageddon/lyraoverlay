import Foundation

/// A request to change the look.
public struct ThemeDecision: Equatable, Sendable {
    public enum Stage: String, Sendable { case initial, cover, audio }

    public var themeID: String
    public var mood: Mood
    public var confidence: Double
    /// What was looked at, short, for a status line: "Rock · 128 BPM · dark cover".
    public var reason: String
    /// The engine's full reasoning, one sentence per source.
    public var details: [String]
    public var stage: Stage

    public init(themeID: String, mood: Mood, confidence: Double, reason: String, details: [String] = [], stage: Stage = .initial) {
        self.themeID = themeID
        self.mood = mood
        self.confidence = confidence
        self.reason = reason
        self.details = details
        self.stage = stage
    }
}

/// The stateful brain behind song-aware theming. The app owns one, tells it what happens, and applies
/// whatever it returns. It has no clock: `now` is any monotonic seconds value (e.g.
/// `ProcessInfo.processInfo.systemUptime`).
///
/// Policy (all numbers in `Policy`):
///  - At track start it decides at once from genre and cover (whichever are enabled and known).
///    It stays quiet when the evidence is thin (confidence below `minConfidence`).
///  - The cover often arrives a moment later: one cheap re-decision is allowed, only within
///    `settleWindow` seconds of the start.
///  - After the audio profile is ready it looks once. It changes the look only when the picture
///    clearly differs from what the look was based on: another mood, confidence at least
///    `switchConfidence`, and a lead over the old mood of at least `audioMargin` (`coverMargin` for the cover).
///    Because genre outweighs audio in `MoodEngine`, a confident genre is not overturned by audio alone.
///  - At most `maxChanges` decisions per track (so no flip-flopping), none in the last `endGuard`
///    seconds of a track (the initial one excepted), and none after `userChoseTheme`.
///  - A decision that would pick the theme already active is not emitted.
///  Limits: a cover re-decision that fires uses the second change, so audio can then not refine; tempo
///  and brightness thresholds are heuristic; elapsed time is `now - start` unless a position is given,
///  so a long pause makes the end guard fire early.
public final class AutoThemeEngine: @unchecked Sendable {
    public struct Policy: Equatable, Sendable {
        public var minConfidence = 0.25
        public var switchConfidence = 0.35
        public var coverMargin = 0.1
        public var audioMargin = 0.2
        public var settleWindow: TimeInterval = 10
        public var endGuard: TimeInterval = 10
        public var maxChanges = 2
        public init() {}
    }

    public var settings: AutoThemeSettings { get { lock.withLock { _settings } } set { lock.withLock { _settings = newValue } } }
    /// The theme currently on screen, so the next pick can differ. Set it when the user (or anything
    /// else) changes the theme; the engine sets it itself when it returns a decision.
    public var activeThemeID: String? { get { lock.withLock { _active } } set { lock.withLock { _active = newValue } } }
    public let policy: Policy
    public let themeIDs: [String]
    public var moodEngine = MoodEngine()

    private let lock = NSLock()
    private var _settings: AutoThemeSettings
    private var _active: String?

    // Per-track state.
    private var trackKey: String?
    private var genre: String?
    private var duration: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var palette: Palette?
    private var profile = AudioProfile()
    private var baselineMood: Mood?
    private var emitted = 0
    private var userChose = false
    private var coverRedecided = false
    private var audioEvaluated = false
    private var _lastDecision: ThemeDecision?

    /// The last decision made for the current track, if any.
    public var lastDecision: ThemeDecision? { lock.withLock { _lastDecision } }
    /// Number of changes emitted for the current track.
    public var changesThisTrack: Int { lock.withLock { emitted } }

    public init(settings: AutoThemeSettings = AutoThemeSettings(), themeIDs: [String], policy: Policy = Policy(),
                profile: AudioProfile = AudioProfile()) {
        _settings = settings
        self.themeIDs = themeIDs
        self.policy = policy
        self.profile = profile
    }

    // MARK: - Events

    public func trackChanged(track: Track?, palette: Palette?, now: TimeInterval) -> ThemeDecision? {
        lock.withLock {
            guard let track else { resetTrack(key: nil); return nil }
            let key = Self.key(for: track)
            if key == trackKey { return nil }   // the same song reported again
            resetTrack(key: key)
            genre = track.genre.trimmingCharacters(in: .whitespacesAndNewlines)
            duration = track.duration
            startedAt = now
            self.palette = palette
            guard _settings.enabled, _settings.usesAnySignal else { return nil }
            return consider(stage: .initial, position: 0)
        }
    }

    /// Feed every analysis tick (any rate; samples closer than a frame are fine).
    public func audio(features: AudioFeatures, now: TimeInterval, position: TimeInterval? = nil) -> ThemeDecision? {
        lock.withLock {
            guard trackKey != nil, _settings.enabled, _settings.useAudio, !audioEvaluated, !userChose, emitted < policy.maxChanges else { return nil }
            profile.add(features, now: now)
            guard profile.isReady else { return nil }
            audioEvaluated = true
            return consider(stage: .audio, position: position ?? (now - startedAt))
        }
    }

    public func palette(_ palette: Palette, now: TimeInterval, position: TimeInterval? = nil) -> ThemeDecision? {
        lock.withLock {
            guard trackKey != nil, self.palette != palette else { return nil }
            self.palette = palette
            guard _settings.enabled, _settings.useCover, !coverRedecided, !userChose, emitted < policy.maxChanges else { return nil }
            let pos = position ?? (now - startedAt)
            guard pos <= policy.settleWindow else { return nil }
            coverRedecided = true
            return consider(stage: .cover, position: pos)
        }
    }

    /// The user picked a theme by hand: no automatic change until the next track.
    public func userChoseTheme(now: TimeInterval) {
        lock.withLock { userChose = true }
    }

    // MARK: - Internals

    private func resetTrack(key: String?) {
        trackKey = key
        genre = nil
        duration = 0
        palette = nil
        profile.reset()
        baselineMood = nil
        emitted = 0
        userChose = false
        coverRedecided = false
        audioEvaluated = false
        _lastDecision = nil
    }

    /// Track identity: the player's id when it has one, otherwise artist, title and album.
    static func key(for t: Track) -> String {
        t.id.isEmpty ? "t:\(t.artist.lowercased())|\(t.title.lowercased())|\(t.album.lowercased())" : "id:\(t.id)"
    }

    private func consider(stage: ThemeDecision.Stage, position: TimeInterval) -> ThemeDecision? {
        guard let key = trackKey, !userChose, emitted < policy.maxChanges else { return nil }
        if stage != .initial, duration > 0, position > duration - policy.endGuard { return nil }

        let genre = _settings.useGenre ? genre.flatMap { $0.isEmpty ? nil : $0 } : nil
        let cover = _settings.useCover ? palette : nil
        let audio = _settings.useAudio ? profile.summary : nil
        let guess = moodEngine.guess(genre: genre, audio: audio, palette: cover)
        guard guess.mood != .neutral else { return nil }

        if let base = baselineMood {
            let margin = stage == .audio ? policy.audioMargin : policy.coverMargin
            guard guess.mood != base, guess.confidence >= policy.switchConfidence,
                  (guess.scores[guess.mood] ?? 0) - (guess.scores[base] ?? 0) >= margin else { return nil }
        } else {
            guard guess.confidence >= policy.minConfidence else { return nil }
        }
        baselineMood = guess.mood

        guard let id = MoodThemes.pick(mood: guess.mood, trackKey: key, activeThemeID: _active, settings: _settings, knownThemeIDs: themeIDs),
              id != _active else { return nil }
        emitted += 1
        _active = id
        let decision = ThemeDecision(themeID: id, mood: guess.mood, confidence: guess.confidence,
                                     reason: Self.lookedAt(genre: genre, audio: audio, palette: cover),
                                     details: guess.reasons, stage: stage)
        _lastDecision = decision
        return decision
    }

    static func lookedAt(genre: String?, audio: AudioSummary?, palette: Palette?) -> String {
        var parts: [String] = []
        if let genre, GenreClassifier.classify(genre) != nil { parts.append(MoodEngine.displayGenre(genre)) }
        if let audio {
            if let t = audio.tempo { parts.append("\(Int(t.rounded())) BPM") }
            parts.append(audio.energy >= 0.55 ? "loud" : audio.energy <= 0.3 ? "quiet" : "moderate energy")
        }
        if let p = palette { parts.append(MoodEngine.describe(p) + " cover") }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " · ")
    }
}
